import CodexKit
import ContextKit
import Foundation
import HeadroomModel
import SessionKit
import SetupKit
import UsageKit

/// Composes UsageKit, SessionKit, ContextKit and SetupKit into one snapshot (spec §3, §4), plus CodexKit and the
/// Copilot CLI records for 1.1's other tools (1.1 §7). Caches parsed files between calls: every file is parsed again
/// only when its (size, mtime) changes, so a poll over unchanged data costs a few dozen `stat`s. Not thread-safe:
/// call `build` from one task at a time.
public final class SnapshotBuilder: @unchecked Sendable {
    public let paths: ClaudePaths
    /// The terminal bridge's install state as of the last `build`, or nil when `~/.claude` wasn't readable or Claude
    /// isn't tracked (or before the first build). Cached like everything else: recomputed only when settings.json or
    /// bridge.sh change.
    public private(set) var bridgeInstallState: BridgeInstallState?
    /// The Claude desktop app's account as of the last `build`: the org of the newest usage-history sample. Every
    /// `.desktopApp` reading in that snapshot comes from this org's samples only (spec §2.1). Nil without desktop
    /// samples, when Claude isn't tracked, or before the first build. Hand it to
    /// `MomentDetector.moments(previous:previousDesktopAccount:current:currentDesktopAccount:)` with the snapshot,
    /// so that switching accounts isn't announced as a limit crossing.
    public private(set) var desktopAccount: String?

    private let probe: any ProcessProbing
    private var desktopUsage: DesktopUsageCache
    private var terminalLimits = TerminalLimitsCache()
    private var registry = DirectoryCache<[RegistryEntry]>()
    private var bridgeRecords = DirectoryCache<[BridgeSessionRecord]>()
    private var bridgeConnection: BridgeConnectionCache
    private let context: SessionContextFiller
    private let subagents = SubagentActivity()
    private var workingRuns = WorkingRuns()
    /// Codex (1.1 §3): one `CodexReader` for the granted folder, kept while the folder stays the same.
    private var codexReader: GrantedFolderReader<any CodexReadingProviding>
    /// Copilot CLI sessions (1.1 §4.9): one reader for the granted folder.
    private var copilotCLIReader: GrantedFolderReader<any CopilotSessionReading>

    public convenience init(paths: ClaudePaths) {
        self.init(paths: paths, probe: SystemProcessProbe())
    }

    /// `probe` decides which session pids are alive (tests pass a fake). Codex liveness checks processes only
    /// (`CodexRuntimeProbe(appIsRunning: { false })`).
    public convenience init(paths: ClaudePaths, probe: any ProcessProbing) {
        self.init(paths: paths, probe: probe, codexRuntime: CodexRuntimeProbe(appIsRunning: { false }))
    }

    /// `codexRuntime` decides Codex liveness (1.1 §3.5): the app passes a `CodexRuntimeProbe` with its NSWorkspace
    /// check, tests a fake. Copilot CLI liveness uses `probe`, like Claude's sessions.
    public convenience init(paths: ClaudePaths, probe: any ProcessProbing, codexRuntime: any CodexRuntimeProbing) {
        self.init(
            paths: paths,
            probe: probe,
            codexReaders: Self.codexReaders(runtime: codexRuntime),
            copilotCLIReaders: Self.copilotCLIReaders(probe: probe)
        )
    }

    /// Tests inject fake Codex and Copilot CLI readers, made per granted folder.
    init(
        paths: ClaudePaths,
        probe: any ProcessProbing,
        codexReaders: @escaping (URL) -> any CodexReadingProviding,
        copilotCLIReaders: @escaping (URL) -> any CopilotSessionReading
    ) {
        self.paths = paths
        self.probe = probe
        desktopUsage = DesktopUsageCache(fileURL: paths.planUsageHistoryFile)
        bridgeConnection = BridgeConnectionCache(claudeDirectory: paths.claudeDirectory)
        context = SessionContextFiller(projectsDirectory: paths.projectsDirectory)
        codexReader = GrantedFolderReader(make: codexReaders)
        copilotCLIReader = GrantedFolderReader(make: copilotCLIReaders)
    }

    /// The 1.0 snapshot: Claude only (`SourceSelection.claudeOnly`, no Copilot usage).
    public func build(access: AccessState, now: Date) -> HeadroomSnapshot {
        build(access: access, sources: .claudeOnly, copilot: nil, now: now)
    }

    /// The multi-tool snapshot (1.1 §7):
    /// - Claude as 1.0 builds it when `sources.claude`; else no Claude reads, no Claude issues, `plan == .empty`, no
    ///   bridge state and no desktop account.
    /// - Codex from `sources.codexHome` when `sources.codex`, rolled over as of `now`. Without a readable grant
    ///   (`AccessState.codexDirectoryReadable` and a `codexHome`): `.needsAccess` and `codexFolderUnavailable`, and
    ///   nothing is read. Its issues (`codexSessionsUnreadable`, `codexUsageUnrecognized`) join Claude's.
    /// - Copilot CLI sessions from `sources.copilotCLIHome` when `sources.copilotCLI` (and the build supports it).
    ///   Without a readable grant: `copilotFolderUnavailable`, and nothing is read.
    /// - `copilot` rolled over as of `now` (the next 1st at 00:00 UTC zeroes the month until the app fetches again),
    ///   or `ToolUsage.copilotSessionsOnly` when it is nil and Copilot CLI sessions are tracked, so Copilot still
    ///   counts as tracked (1.1 §4.8). Nil otherwise: the app passes nil while Copilot isn't tracked.
    /// - Every tool's sessions merged and sorted with `sortedForDisplay()`.
    public func build(access: AccessState, sources: SourceSelection, copilot: ToolUsage?, now: Date) -> HeadroomSnapshot {
        var snapshot: HeadroomSnapshot
        if sources.claude {
            snapshot = buildClaude(access: access, now: now)
        } else {
            snapshot = .empty(at: now)
            snapshot.claudeTracked = false
            bridgeInstallState = nil
            desktopAccount = nil
        }

        if sources.codex {
            if access.codexDirectoryReadable, let home = sources.codexHome {
                let reading = codexReader.reader(for: home).read(now: now)
                snapshot.codex = reading.usage.rolledOver(now: now)
                // 1.1 §14.12: with no Codex session working here, the reading is the latest one this Mac can have.
                if !reading.sessions.contains(where: { $0.activity == .working }) {
                    snapshot.codex?.quietSinceReading = true
                }
                snapshot.sessions += reading.sessions
                snapshot.issues.formUnion(reading.issues)
            } else {
                snapshot.codex = ToolUsage(tool: .codex, status: .needsAccess)
                snapshot.issues.insert(.codexFolderUnavailable)
            }
        } else {
            codexReader.release()
        }

        if sources.readsCopilotCLI {
            if access.copilotDirectoryReadable, let home = sources.copilotCLIHome {
                snapshot.sessions += copilotCLIReader.reader(for: home).readSessions(now: now)
            } else {
                snapshot.issues.insert(.copilotFolderUnavailable)
            }
        } else {
            copilotCLIReader.release()
        }
        snapshot.copilot = (copilot ?? (sources.readsCopilotCLI ? .copilotSessionsOnly : nil))?.rolledOver(now: now)

        snapshot.sessions = workingRuns.applied(to: snapshot.sessions).sortedForDisplay()
        return snapshot
    }

    /// Claude's part (spec §2, §3), sessions unsorted.
    private func buildClaude(access: AccessState, now: Date) -> HeadroomSnapshot {
        var issues = Set<DataIssue>()

        // Desktop usage history (spec §2.1).
        var desktopSamples: [DesktopUsageSample] = []
        if access.desktopDirectoryReadable {
            let result = desktopUsage.samples(now: now)
            desktopSamples = result.samples
            if result.unrecognized { issues.insert(.desktopUsageUnrecognized) }
        } else if access.desktopAppInstalled {
            issues.insert(.desktopFolderUnavailable)
        }
        desktopAccount = DesktopUsageAnalyzer.newestOrg(of: desktopSamples)

        // Everything under ~/.claude: terminal limits, sessions, context, bridge state (spec §2.2–2.6).
        var terminal: PlanUsage?
        var sessions: [SessionInfo] = []
        if access.claudeDirectoryReadable {
            terminal = readTerminalLimits()
            sessions = readSessions(now: now, issues: &issues)
            bridgeInstallState = bridgeConnection.state()
        } else {
            issues.insert(.claudeCodeFolderUnavailable)
            bridgeInstallState = nil
        }

        let plan = PlanUsageResolver.resolve(
            desktop: DesktopUsageAnalyzer.currentUsage(samples: desktopSamples, now: now),
            desktopSamples: desktopSamples,
            terminal: terminal,
            now: now
        )
        return HeadroomSnapshot(
            plan: plan,
            sessions: sessions,
            terminalBridgeConnected: bridgeInstallState.map(BridgeConnectionCache.isConnected) ?? false,
            issues: issues,
            generatedAt: now
        )
    }

    private func readTerminalLimits() -> PlanUsage? {
        terminalLimits.value(from: TerminalLimitsReader(fileURL: paths.statusLineLatestFile))
    }

    /// Registry + bridge sessions, merged, with context filled in and background work counted. Liveness is checked on
    /// every call.
    private func readSessions(now: Date, issues: inout Set<DataIssue>) -> [SessionInfo] {
        let entries: [RegistryEntry]
        do {
            let reader = SessionRegistryReader(directory: paths.sessionsDirectory)
            entries = try registry.value(of: reader.directory, including: Self.isJSONFile) { try reader.readEntries() }
        } catch {
            issues.insert(.sessionRegistryUnreadable)
            entries = []
        }
        let bridgeReader = BridgeSessionReader(directory: paths.bridgeSessionsDirectory)
        let records = bridgeRecords.value(of: bridgeReader.directory, including: Self.isJSONFile) {
            bridgeReader.readRecords()
        }
        let merged = SessionMerger.merge(registry: entries, bridge: records, probe: probe, now: now)
        return countingBackgroundWork(context.filling(merged, bridge: records), now: now)
    }

    /// 1.1 §14.11: a session idle between turns while a background task (a shell child: a Bash command or monitor),
    /// or a background agent still runs is working, as Claude's own "running task" count says. Waiting stays waiting.
    private func countingBackgroundWork(_ sessions: [SessionInfo], now: Date) -> [SessionInfo] {
        guard sessions.contains(where: { $0.activity == .idle }) else { return sessions }
        let shellParents = probe.shellParents()
        return sessions.map { session in
            guard session.activity == .idle,
                  session.pid.map(shellParents.contains) == true || hasRunningAgent(session, now: now)
            else { return session }
            var session = session
            session.activity = .working
            return session
        }
    }

    private func hasRunningAgent(_ session: SessionInfo, now: Date) -> Bool {
        guard let path = session.transcriptPath else { return false }
        return subagents.hasRunningAgent(transcript: URL(fileURLWithPath: path), now: now)
    }

    /// Both session directories hold `*.json` files the readers parse; other files (`*.key`, sockets) don't matter.
    private static func isJSONFile(_ name: String) -> Bool {
        name.hasSuffix(".json")
    }

    // MARK: - Instrumentation

    /// How often each source was actually read (for tests; transcripts are counted by ContextKit, Codex and Copilot
    /// CLI reads by the readers).
    struct Statistics: Equatable {
        var desktopReads = 0
        var terminalReads = 0
        var registryReads = 0
        var bridgeReads = 0
        var bridgeStateChecks = 0
    }

    var statistics: Statistics {
        Statistics(
            desktopReads: desktopUsage.reads,
            terminalReads: terminalLimits.reads,
            registryReads: registry.reads,
            bridgeReads: bridgeRecords.reads,
            bridgeStateChecks: bridgeConnection.checks
        )
    }

    /// Readers made for granted folders so far (for tests).
    var readersMade: (codex: Int, copilotCLI: Int) {
        (codexReader.made, copilotCLIReader.made)
    }
}
