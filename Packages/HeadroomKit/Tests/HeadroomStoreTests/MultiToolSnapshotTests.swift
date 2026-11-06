import CodexKit
import Foundation
import HeadroomModel
import SetupKit
import Testing
@testable import HeadroomStore

/// 1.1 §7: `build(access:sources:copilot:now:)` composes Claude, Codex, Copilot CLI sessions and Copilot usage.
@Suite struct MultiToolSnapshotTests {
    /// Claude data in every source, so a test can tell which ones were read.
    private func populated(_ fixture: ToolFixture) throws {
        try fixture.tree.writeDesktopHistory([HistorySample(time: testNow - 10 * minute, fiveHour: 14, weekly: 89)])
        try fixture.tree.writeStatusLineLatest(
            fiveHour: (20, testNow + 2 * hour), weekly: (90, testNow + 72 * hour), modified: testNow - minute)
        try fixture.tree.writeRegistryEntry(sessionId: "desk-1", pid: 101, status: "busy", statusUpdatedAt: testNow - 3 * minute)
        try fixture.tree.writeBridgeHook(sessionId: "term-1", pid: 202, event: "Stop", at: testNow - 20 * minute)
        try BridgeInstaller(claudeDirectory: fixture.tree.paths.claudeDirectory).install()
    }

    @Test func everyToolInOneSnapshot() throws {
        let fixture = try ToolFixture(probe: FakeProcessProbe(alive: [101, 202]))
        defer { fixture.remove() }
        try populated(fixture)
        let codex = codexUsage(weekly: 42, fiveHour: 17, at: testNow - 5 * minute)
        fixture.readers.codexReading = CodexReading(
            usage: codex,
            sessions: [
                codexSession("t-working", .working, since: testNow - minute),
                codexSession("t-idle", .idle, since: testNow - 2 * hour, name: "atlas"),
            ],
            issues: [])
        fixture.readers.copilotCLISessions = [copilotCLISession("c-wait", .waitingForInput, since: testNow - 30 * second)]
        let copilot = copilotUsage(used: 512, allowance: 1_500, at: testNow - 10 * minute)

        let snapshot = fixture.build(copilot: copilot, now: testNow)

        #expect(snapshot.claudeTracked)
        #expect(snapshot.plan.weekly?.usedPercent == 90)
        #expect(snapshot.codex == codex)
        #expect(snapshot.copilot == copilot)
        #expect(snapshot.trackedTools == [.claude, .codex, .copilot])
        #expect(snapshot.terminalBridgeConnected)
        #expect(snapshot.issues.isEmpty)
        #expect(snapshot.generatedAt == testNow)
        // One list for every tool: working, then waiting, then idle; most recent activity first in a group.
        #expect(snapshot.sessions.map(\.id) == ["codex:t-working", "desk-1", "copilot:c-wait", "term-1", "codex:t-idle"])
        #expect(snapshot.sessions.map(\.tool) == [.codex, .claude, .copilot, .claude, .codex])
    }

    /// 1.1 §14.12: Codex's reading is quiet while no Codex session here is working.
    @Test func codexReadingIsQuietWithoutAWorkingSession() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let codex = codexUsage(weekly: 42, at: testNow - 2 * hour)
        fixture.readers.codexReading = CodexReading(
            usage: codex, sessions: [codexSession("t-idle", .idle, since: testNow - hour)], issues: [])
        #expect(fixture.build(copilot: nil, now: testNow).codex?.quietSinceReading == true)

        fixture.readers.codexReading = CodexReading(
            usage: codex, sessions: [codexSession("t-working", .working, since: testNow - minute)], issues: [])
        #expect(fixture.build(copilot: nil, now: testNow).codex?.quietSinceReading == nil)
    }

    /// The Codex reader's context and names are kept as they are: the Claude context filler never sees them.
    @Test func codexSessionsKeepTheirOwnContext() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let session = codexSession("t-1", .working, since: testNow - minute)
        fixture.readers.codexReading = CodexReading(usage: codexUsage(weekly: 42, at: testNow), sessions: [session], issues: [])

        let snapshot = fixture.build(now: testNow)

        #expect(snapshot.sessions == [session])
    }

    @Test func issuesFromEveryToolAreJoined() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        fixture.readers.codexReading = CodexReading(
            usage: ToolUsage(tool: .codex, status: .unrecognized), sessions: [],
            issues: [.codexUsageUnrecognized, .codexSessionsUnreadable])
        let access = AccessState(
            claudeDirectoryReadable: false, desktopDirectoryReadable: false, desktopAppInstalled: true,
            codexDirectoryReadable: true, copilotDirectoryReadable: false)

        let snapshot = fixture.build(access: access, now: testNow)

        var expected: Set<DataIssue> = [
            .claudeCodeFolderUnavailable, .desktopFolderUnavailable, .codexUsageUnrecognized, .codexSessionsUnreadable,
        ]
        #if HEADROOM_COPILOT_CLI
        expected.insert(.copilotFolderUnavailable)
        #endif
        #expect(snapshot.issues == expected)
        #expect(snapshot.codex?.status == .unrecognized)
    }

    // MARK: - Claude untracked

    @Test func claudeUntrackedReadsNothingOfClaudes() throws {
        let fixture = try ToolFixture(probe: FakeProcessProbe(alive: [101, 202]))
        defer { fixture.remove() }
        try populated(fixture)
        fixture.readers.codexReading = CodexReading(
            usage: codexUsage(weekly: 42, at: testNow), sessions: [codexSession("t-1", .idle, since: testNow)], issues: [])
        var sources = fixture.allSources
        sources.claude = false

        let snapshot = fixture.build(sources: sources, now: testNow)

        #expect(!snapshot.claudeTracked)
        #expect(snapshot.plan == .empty)
        #expect(snapshot.sessions.map(\.id) == ["codex:t-1"])
        #expect(!snapshot.terminalBridgeConnected)
        #expect(snapshot.issues.isEmpty)
        #expect(!snapshot.trackedTools.contains(.claude))
        #expect(snapshot.trackedTools.first == .codex)
        #expect(fixture.builder.statistics == SnapshotBuilder.Statistics())
        #expect(fixture.builder.bridgeInstallState == nil)
        #expect(fixture.builder.desktopAccount == nil)
    }

    /// Unreadable Claude folders aren't Claude issues while Claude isn't tracked.
    @Test func claudeUntrackedHasNoClaudeIssues() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let sources = SourceSelection(claude: false, codex: true, codexHome: fixture.codexHome)

        let snapshot = fixture.build(access: AccessState(
            claudeDirectoryReadable: false, desktopDirectoryReadable: false, desktopAppInstalled: true,
            codexDirectoryReadable: true
        ), sources: sources, now: testNow)

        #expect(snapshot.issues.isEmpty)
        #expect(snapshot.codex?.status == .noActivity)
    }

    /// Turning Claude off drops what the last build learned about it; turning it back on reads it again.
    @Test func claudeTrackedAgainIsReadAgain() throws {
        let fixture = try ToolFixture(probe: FakeProcessProbe(alive: [101, 202]))
        defer { fixture.remove() }
        try populated(fixture)
        let tracked = fixture.build(now: testNow - 4 * second)
        #expect(fixture.builder.bridgeInstallState == .installed)
        #expect(fixture.builder.desktopAccount == "org-a")

        var sources = fixture.allSources
        sources.claude = false
        _ = fixture.build(sources: sources, now: testNow - 2 * second)
        #expect(fixture.builder.bridgeInstallState == nil)
        #expect(fixture.builder.desktopAccount == nil)

        let again = fixture.build(now: testNow)
        #expect(again.plan == tracked.plan)
        #expect(again.sessions.map(\.id) == tracked.sessions.map(\.id))
        #expect(fixture.builder.bridgeInstallState == .installed)
        #expect(fixture.builder.desktopAccount == "org-a")
    }

    /// Nothing tracked at all: an empty snapshot that tracks no tool.
    @Test func nothingTracked() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }

        let snapshot = fixture.build(access: .none, sources: SourceSelection(claude: false), now: testNow)

        #expect(snapshot.trackedTools.isEmpty)
        #expect(snapshot.issues.isEmpty)
        #expect(snapshot.sessions.isEmpty)
        #expect(fixture.readers.codex.isEmpty)
        #expect(fixture.readers.copilotCLI.isEmpty)
    }

    // MARK: - Codex (1.1 §3)

    @Test func codexWithoutAccessNeedsAccessAndReadsNothing() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        var noGrant = fixture.allSources
        noGrant.codexHome = nil
        var unreadable = AccessState.everything
        unreadable.codexDirectoryReadable = false

        for (access, sources) in [(unreadable, fixture.allSources), (AccessState.everything, noGrant)] {
            let snapshot = fixture.build(access: access, sources: sources, now: testNow)

            #expect(snapshot.codex == ToolUsage(tool: .codex, status: .needsAccess))
            #expect(snapshot.issues == [.codexFolderUnavailable])
            #expect(snapshot.trackedTools.contains(.codex))
        }
        #expect(fixture.readers.codex.isEmpty)
    }

    @Test func codexUntrackedIsNil() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        var sources = fixture.allSources
        sources.codex = false

        let snapshot = fixture.build(sources: sources, now: testNow)

        #expect(snapshot.codex == nil)
        #expect(!snapshot.trackedTools.contains(.codex))
        #expect(fixture.readers.codex.isEmpty)
    }

    /// One reader per granted folder, kept (with its caches) while the folder stays the same and Codex tracked.
    @Test func theCodexReaderIsKeptWhileTheFolderStaysTheSame() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        var sources = fixture.allSources

        _ = fixture.build(sources: sources, now: testNow - 6 * second)
        sources.codexHome = URL(fileURLWithPath: fixture.codexHome.path + "/")
        _ = fixture.build(sources: sources, now: testNow - 4 * second)
        #expect(fixture.readers.codex.count == 1)
        #expect(fixture.readers.codex.first?.reads == 2)
        #expect(fixture.readers.codex.first?.home == fixture.codexHome)

        let other = fixture.tree.root.appendingPathComponent("codex-home", isDirectory: true)
        sources.codexHome = other
        _ = fixture.build(sources: sources, now: testNow - 2 * second)
        #expect(fixture.readers.codex.map(\.home) == [fixture.codexHome, other])

        // Not tracked: the reader is dropped; tracked again: a fresh one.
        sources.codex = false
        _ = fixture.build(sources: sources, now: testNow - second)
        sources.codex = true
        _ = fixture.build(sources: sources, now: testNow)
        #expect(fixture.readers.codex.map(\.home) == [fixture.codexHome, other, other])
        #expect(fixture.readers.codex.map(\.reads) == [2, 1, 1])
        #expect(fixture.builder.readersMade.codex == 3)
    }

    /// Codex's limits are rolled over on every build (1.1 §3.4): readings are seen up to a minute past `resets_at`.
    @Test func codexLimitsAreRolledOverAsOfTheBuild() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let weekly = toolLimit(.weekly, 97, at: testNow - 2 * hour, resetsAt: testNow - minute)
        let fiveHour = toolLimit(.fiveHour, 40, at: testNow - 2 * hour, resetsAt: testNow + hour)
        fixture.readers.codexReading = CodexReading(
            usage: ToolUsage(tool: .codex, limits: [weekly, fiveHour], hasFiveHourWindow: true, status: .ok),
            sessions: [], issues: [])

        let snapshot = fixture.build(now: testNow)

        let rolled = try #require(snapshot.codex?.limit(.weekly))
        #expect(rolled.usedPercent == 0)
        #expect(rolled.resetsAt == nil)
        #expect(rolled.resetSinceReading)
        #expect(snapshot.codex?.limit(.fiveHour) == fiveHour)
    }

    // MARK: - Copilot (1.1 §4)

    @Test func copilotUsageIsPassedThrough() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        var sources = fixture.allSources
        sources.copilotCLI = false
        let copilot = copilotUsage(used: 512, allowance: nil, at: testNow - 10 * minute)

        #expect(fixture.build(sources: sources, copilot: copilot, now: testNow).copilot == copilot)
        #expect(fixture.build(sources: sources, copilot: nil, now: testNow).copilot == nil)
        let notConnected = ToolUsage(tool: .copilot, status: .notConnected)
        #expect(fixture.build(sources: sources, copilot: notConnected, now: testNow).copilot == notConnected)
    }

    /// GitHub's month ends at 00:00 UTC on the 1st: until the app fetches again, the month shows 0 used.
    @Test func copilotUsageRollsOverAtTheUTCMonth() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let october = Date(timeIntervalSince1970: 1_790_812_800)
        let november = Date(timeIntervalSince1970: 1_793_491_200)
        let copilot = copilotUsage(used: 1_400, allowance: 1_500, at: october - hour, resetsAt: october)

        let before = fixture.build(copilot: copilot, now: october - minute)
        let after = fixture.build(copilot: copilot, now: october + hour)

        #expect(before.copilot == copilot)
        let rolled = try #require(after.copilot?.limits.first)
        #expect(rolled.used == 0)
        #expect(rolled.usedPercent == 0)
        #expect(rolled.resetsAt == november)
        #expect(rolled.observedAt == october - hour)
    }

    #if HEADROOM_COPILOT_CLI
    @Test func copilotCLISessionsWithoutUsageTrackCopilotAsSessionsOnly() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        fixture.readers.copilotCLISessions = [copilotCLISession("c-1", .working, since: testNow - minute)]

        let snapshot = fixture.build(copilot: nil, now: testNow)

        #expect(snapshot.copilot == .copilotSessionsOnly)
        #expect(snapshot.trackedTools.contains(.copilot))
        #expect(snapshot.sessions.map(\.id) == ["copilot:c-1"])
    }

    @Test func copilotUsageWinsOverSessionsOnly() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let copilot = copilotUsage(used: 512, allowance: 1_500, at: testNow - 10 * minute)

        #expect(fixture.build(copilot: copilot, now: testNow).copilot == copilot)
    }

    @Test func copilotCLIWithoutAccessIsAnIssueAndReadsNothing() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        var noGrant = fixture.allSources
        noGrant.copilotCLIHome = nil
        var unreadable = AccessState.everything
        unreadable.copilotDirectoryReadable = false

        for (access, sources) in [(unreadable, fixture.allSources), (AccessState.everything, noGrant)] {
            let snapshot = fixture.build(access: access, sources: sources, now: testNow)

            #expect(snapshot.issues == [.copilotFolderUnavailable])
            #expect(snapshot.copilot == .copilotSessionsOnly)
        }
        #expect(fixture.readers.copilotCLI.isEmpty)
    }

    @Test func theCopilotCLIReaderIsKeptWhileTheFolderStaysTheSame() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        var sources = fixture.allSources

        _ = fixture.build(sources: sources, now: testNow - 4 * second)
        _ = fixture.build(sources: sources, now: testNow - 2 * second)
        sources.copilotCLI = false
        let untracked = fixture.build(sources: sources, now: testNow)

        #expect(untracked.copilot == nil)
        #expect(fixture.readers.copilotCLI.map(\.reads) == [2])
        #expect(fixture.builder.readersMade.copilotCLI == 1)
    }

    /// Copilot CLI's hooks rewrite a working session's record on every tool call, moving its `activitySince`. The
    /// builder keeps the start of the working run, as for Claude's terminal sessions, so a long run can finish.
    @Test func aCopilotCLIWorkingRunKeepsItsStart() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let start = testNow - minute
        fixture.readers.copilotCLISessions = [copilotCLISession("c-1", .working, since: start)]
        _ = fixture.build(now: testNow - 4 * second)

        fixture.readers.copilotCLISessions = [copilotCLISession("c-1", .working, since: testNow - 3 * second)]
        let working = fixture.build(now: testNow - 2 * second)
        #expect(working.sessions.first?.activitySince == start)

        fixture.readers.copilotCLISessions = [copilotCLISession("c-1", .idle, since: testNow - second)]
        let idle = fixture.build(now: testNow)
        #expect(MomentDetector.moments(previous: working, current: idle) == [
            .sessionFinished(sessionID: "copilot:c-1", name: "harbor"),
        ])
    }
    #endif

    // MARK: - 1.0 compatibility

    /// `build(access:now:)` is the Claude-only selection without Copilot usage.
    @Test func theClaudeOnlyBuildIsTheOneZeroSnapshot() throws {
        let fixture = try ToolFixture(probe: FakeProcessProbe(alive: [101, 202]))
        defer { fixture.remove() }
        try populated(fixture)

        let legacy = fixture.builder.build(access: .full, now: testNow)
        let selected = fixture.builder.build(access: .full, sources: .claudeOnly, copilot: nil, now: testNow)

        #expect(legacy == selected)
        #expect(legacy.sessions.map(\.id) == ["desk-1", "term-1"])
        #expect(legacy.claudeTracked && legacy.codex == nil && legacy.copilot == nil)
        #expect(legacy.isClaudeOnly)
        #expect(fixture.readers.codex.isEmpty && fixture.readers.copilotCLI.isEmpty)
    }

    // MARK: - The real readers

    /// The public initializers read a granted Codex folder through CodexKit's `CodexReader`: an empty one has no
    /// limits.
    @Test func thePublicInitializerReadsCodexThroughCodexKit() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        let codexHome = tree.root.appendingPathComponent("codex", isDirectory: true)
        try FileManager.default.createDirectory(
            at: CodexPaths(codexDirectory: codexHome).sessionsDirectory, withIntermediateDirectories: true)
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(), codexRuntime: NoCodexRunning())
        let sources = SourceSelection(claude: false, codex: true, copilotCLI: true, codexHome: codexHome,
                                      copilotCLIHome: tree.root.appendingPathComponent("copilot", isDirectory: true))

        let snapshot = builder.build(access: .everything, sources: sources, copilot: nil, now: testNow)

        #expect(snapshot.codex?.status == .noActivity)
        #expect(snapshot.codex?.limits.isEmpty == true)
        #expect(snapshot.sessions.isEmpty)
        #expect(builder.readersMade.codex == 1)
    }
}

private struct NoCodexRunning: CodexRuntimeProbing {
    func codexRunning() -> Bool? { false }
}
