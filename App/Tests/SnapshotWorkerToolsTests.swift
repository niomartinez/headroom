import Foundation
import HeadroomModel
import HeadroomStore
import SetupKit
import Testing

/// The poll's worker with 1.1's tools (§7): the sources it builds from the tracked tools and the grants, Codex's
/// limits, Claude untracked, and Connect Copilot CLI's state. Every folder is a temporary one.
@Suite struct SnapshotWorkerToolsTests {
    private func makeHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeadroomSnapshotWorkerToolsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func check(home: URL, codexGranted: Bool = true, copilotGranted: Bool = true) -> AccessCheck {
        let paths = ClaudePaths.standard(home: home)
        let codex = CodexPaths.standard(home: home).codexDirectory
        let copilot = CopilotPaths.standard(home: home).copilotDirectory
        return AccessCheck(
            paths: paths,
            claudeGranted: true,
            desktopGranted: false,
            claudeCodeLocation: paths.claudeDirectory,
            desktopAppInstalled: false,
            generation: 0,
            tools: AccessCheck.ToolFolders(
                codexDirectory: codex, codexGranted: codexGranted, codexLocation: codex, codexAppInstalled: false,
                copilotDirectory: copilot, copilotGranted: copilotGranted, copilotLocation: copilot
            )
        )
    }

    /// 2026-09-23T10:05:00Z, a few minutes after the made-up rollout's reading.
    private let now = Date(timeIntervalSince1970: 1_790_157_900)

    /// A made-up Plus rollout (1.1 §3.2): 5-hour 17 %, weekly 55 %, read at 10:02 UTC.
    private func writeCodexRollout(home: URL) throws {
        let thread = "01a0cdb5-3500-7eec-8529-5f75fffebd3e"
        let day = CodexPaths.standard(home: home).sessionsDirectory.appendingPathComponent("2026/09/23", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let lines = [
            #"{"timestamp":"2026-09-23T10:00:00.000Z","type":"session_meta","payload":{"id":"\#(thread)","session_id":"\#(thread)","timestamp":"2026-09-23T10:00:00.000Z","cwd":"/Users/me/code/app","originator":"Codex Desktop","cli_version":"0.153.4","source":"vscode","thread_source":"user"}}"#,
            #"{"timestamp":"2026-09-23T10:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":149000,"cached_input_tokens":148000,"output_tokens":1000,"reasoning_output_tokens":300,"total_tokens":150000},"model_context_window":258400},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":17.0,"window_minutes":300,"resets_at":1790170000},"secondary":{"used_percent":55.0,"window_minutes":10080,"resets_at":1790700000},"plan_type":"plus"}}}"#,
        ]
        try Data((lines.joined(separator: "\n") + "\n").utf8)
            .write(to: day.appendingPathComponent("rollout-2026-09-23T10-00-00-\(thread).jsonl"))
    }

    // MARK: Codex

    @Test func aTrackedCodexShowsItsLimits() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeCodexRollout(home: home)
        let tracking = ToolTracking(claude: true, codex: true, copilot: false)

        let result = await SnapshotWorker().refresh(check: check(home: home), tracking: tracking, lookUpDesktopApp: { false }, now: now)
        #expect(result.sources.codex)
        #expect(result.sources.codexHome == CodexPaths.standard(home: home).codexDirectory)
        #expect(result.snapshot.trackedTools == [.claude, .codex])
        let codex = try #require(result.snapshot.codex)
        #expect(codex.status == .ok)
        #expect(codex.planName == "Plus")
        #expect(codex.limit(.weekly)?.usedPercent == 55)
        #expect(codex.limit(.fiveHour)?.usedPercent == 17)
        #expect(codex.hasFiveHourWindow)
    }

    @Test func anUndecidedOrDeclinedCodexIsNotRead() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeCodexRollout(home: home)
        for codex in [nil, false] as [Bool?] {
            let tracking = ToolTracking(claude: true, codex: codex, copilot: false)
            let result = await SnapshotWorker().refresh(check: check(home: home), tracking: tracking, lookUpDesktopApp: { false }, now: now)
            #expect(!result.sources.codex)
            #expect(result.snapshot.codex == nil)
            #expect(result.snapshot.isClaudeOnly)
        }
    }

    /// Tracked but not granted: the access row asks for `~/.codex`, and nothing is read.
    @Test func aTrackedCodexWithoutAccessAsksForIt() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeCodexRollout(home: home)
        let tracking = ToolTracking(claude: true, codex: true, copilot: false)

        let result = await SnapshotWorker().refresh(
            check: check(home: home, codexGranted: false), tracking: tracking, lookUpDesktopApp: { false }, now: now
        )
        #expect(result.snapshot.codex?.status == .needsAccess)
        #expect(result.snapshot.codex?.limits.isEmpty == true)
        #expect(result.snapshot.issues.contains(.codexFolderUnavailable))
    }

    // MARK: Claude untracked

    @Test func anUntrackedClaudeIsNotRead() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeCodexRollout(home: home)
        let tracking = ToolTracking(claude: false, codex: true, copilot: false)

        // ~/.claude isn't even there: tracked, that would be an access issue.
        let result = await SnapshotWorker().refresh(check: check(home: home), tracking: tracking, lookUpDesktopApp: { false }, now: now)
        #expect(!result.snapshot.claudeTracked)
        #expect(result.snapshot.plan.isEmpty)
        #expect(result.snapshot.trackedTools == [.codex])
        #expect(!result.snapshot.issues.contains(.claudeCodeFolderUnavailable))
        #expect(result.bridgeState == nil)
    }

    // MARK: Copilot

    /// Copilot's usage comes from the app's service, and only while Copilot is tracked.
    @Test func copilotUsageIsUsedOnlyWhileTracked() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let usage = ToolUsage(tool: .copilot, status: .notConnected)

        let untracked = await SnapshotWorker().refresh(
            check: check(home: home), tracking: .claudeOnly, copilot: usage, lookUpDesktopApp: { false }, now: now
        )
        #expect(untracked.snapshot.copilot == nil)

        let tracked = await SnapshotWorker().refresh(
            check: check(home: home), tracking: ToolTracking(claude: true, codex: nil, copilot: true), copilot: usage,
            lookUpDesktopApp: { false }, now: now
        )
        #expect(tracked.snapshot.copilot == usage)
        #expect(tracked.snapshot.trackedTools == [.claude, .copilot])
    }

    /// Connect Copilot CLI through the worker, into a temporary `~/.copilot`: its state follows, and its sessions are
    /// read once Copilot is tracked.
    @Test func connectingCopilotCLIIsSeenByTheNextPoll() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let copilot = CopilotPaths.standard(home: home).copilotDirectory
        let worker = SnapshotWorker()
        let tracking = ToolTracking(claude: true, codex: nil, copilot: true)

        let absent = await worker.refresh(check: check(home: home), tracking: tracking, lookUpDesktopApp: { false }, now: now)
        #expect(absent.copilotCLIState == nil)
        #expect(!absent.access.state.copilotCLIInstalled)

        try FileManager.default.createDirectory(at: copilot.appendingPathComponent("logs"), withIntermediateDirectories: true)
        let before = await worker.refresh(check: check(home: home), tracking: tracking, lookUpDesktopApp: { false }, now: now)
        #expect(before.copilotCLIState == .notInstalled)
        #expect(!before.sources.copilotCLI)
        #expect(!before.hasCopilotCLILeftovers)
        #expect(before.snapshot.copilot == nil)

        let plan = await worker.copilotCLIInstallPlan(copilotDirectory: copilot)
        #expect(plan.contains { $0.path.hasSuffix("hooks/headroom.json") && $0.verb == "Create" })
        #expect(CopilotCLIConsent.text(CopilotCLIConsent.connectMessage, changes: plan).contains("• Create "))

        try await worker.installCopilotCLI(copilotDirectory: copilot)
        let after = await worker.refresh(check: check(home: home), tracking: tracking, lookUpDesktopApp: { false }, now: now)
        #expect(after.copilotCLIState == .installed)
        #expect(after.sources.copilotCLI)
        #expect(after.sources.copilotCLIHome == copilot)
        // No usage handed over (no Client ID): tracked for its sessions only.
        #expect(after.snapshot.copilot == .copilotSessionsOnly)

        // Not tracked: its state still shows in Settings, but its sessions aren't read.
        let untracked = await worker.refresh(check: check(home: home), tracking: .claudeOnly, lookUpDesktopApp: { false }, now: now)
        #expect(untracked.copilotCLIState == .installed)
        #expect(!untracked.sources.copilotCLI)

        try await worker.uninstallCopilotCLI(copilotDirectory: copilot)
        let disconnected = await worker.refresh(check: check(home: home), tracking: tracking, lookUpDesktopApp: { false }, now: now)
        #expect(disconnected.copilotCLIState == .notInstalled)
        #expect(!disconnected.hasCopilotCLILeftovers)
        #expect(!FileManager.default.fileExists(atPath: CopilotPaths.standard(home: home).hooksFile.path))
    }

    /// The state is read again when the hooks file changes behind the worker's back.
    @Test func anEditedHooksFileIsNoticed() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = CopilotPaths.standard(home: home)
        try FileManager.default.createDirectory(at: paths.copilotDirectory, withIntermediateDirectories: true)
        let worker = SnapshotWorker()
        try await worker.installCopilotCLI(copilotDirectory: paths.copilotDirectory)
        let installed = await worker.refresh(check: check(home: home), lookUpDesktopApp: { false }, now: now)
        #expect(installed.copilotCLIState == .installed)

        try Data(#"{"version":1,"hooks":{}}"#.utf8).write(to: paths.hooksFile)
        let edited = await worker.refresh(check: check(home: home), lookUpDesktopApp: { false }, now: now)
        #expect(edited.copilotCLIState == .outdated)
    }

    @Test func anUngrantedCopilotFolderHasNoState() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: CopilotPaths.standard(home: home).copilotDirectory, withIntermediateDirectories: true)
        let result = await SnapshotWorker().refresh(
            check: check(home: home, copilotGranted: false), tracking: ToolTracking(claude: true, codex: nil, copilot: true),
            lookUpDesktopApp: { false }, now: now
        )
        #expect(result.copilotCLIState == nil)
        #expect(result.access.state.copilotCLIInstalled)
        #expect(!result.sources.copilotCLI)
    }
}
