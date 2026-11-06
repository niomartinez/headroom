import Foundation
import HeadroomModel
import Testing
@testable import SessionKit

private func entry(
    _ id: String,
    pid: Int32,
    entrypoint: String? = "claude-desktop",
    status: String? = "idle",
    name: String? = "Polish onboarding copy",
    cwd: String? = "/Users/tester/code/sample-app",
    startedAt: Date? = testNow - minutes(120),
    statusUpdatedAt: Date? = testNow - minutes(10),
    nameSource: String? = nil,
    processStartedAt: Date? = nil,
    waitingFor: String? = nil,
    version: String? = nil,
    hostSessionId: String? = nil
) -> RegistryEntry {
    RegistryEntry(
        sessionId: id, pid: pid, cwd: cwd, entrypoint: entrypoint, kind: "interactive",
        status: status, name: name, startedAt: startedAt, statusUpdatedAt: statusUpdatedAt,
        nameSource: nameSource, processStartedAt: processStartedAt, waitingFor: waitingFor, version: version,
        hostSessionId: hostSessionId)
}

private func merge(
    _ registry: [RegistryEntry] = [],
    _ bridge: [BridgeSessionRecord] = [],
    alive: Set<Int32>,
    startTimes: [Int32: Date] = [:]
) -> [SessionInfo] {
    SessionMerger.merge(
        registry: registry, bridge: bridge,
        probe: FakeProcessProbe(alive: alive, startTimes: startTimes), now: testNow)
}

@Suite struct RegistryFilteringTests {
    @Test func includesDesktopAndCliEntrypointsOnly() {
        let sessions = merge([
            entry("desktop", pid: 1, entrypoint: "claude-desktop"),
            entry("desktop-variant", pid: 2, entrypoint: "claude-desktop-preview"),
            entry("cli", pid: 3, entrypoint: "cli"),
            entry("sdk-cli", pid: 4, entrypoint: "sdk-cli"),
            entry("sdk-ts", pid: 5, entrypoint: "sdk-ts"),
            entry("none", pid: 6, entrypoint: nil),
            entry("other", pid: 7, entrypoint: "vscode"),
        ], alive: [1, 2, 3, 4, 5, 6, 7])

        #expect(Set(sessions.map(\.id)) == ["desktop", "desktop-variant", "cli"])
    }

    @Test func excludesDeadPids() {
        let sessions = merge([
            entry("alive", pid: 10),
            entry("dead", pid: 11),
        ], alive: [10])

        #expect(sessions.map(\.id) == ["alive"])
    }

    @Test func mapsRegistryStatus() {
        let sessions = merge([
            entry("a", pid: 1, status: "busy"),
            entry("b", pid: 2, status: "waiting_for_permission"),
            entry("c", pid: 3, status: "idle"),
            entry("d", pid: 4, status: nil),
        ], alive: [1, 2, 3, 4])

        let activities = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.activity) })
        #expect(activities == ["a": .working, "b": .waitingForInput, "c": .idle, "d": .idle])
    }

    @Test func duplicateSessionIdKeepsTheNewestEntry() {
        let sessions = merge([
            entry("same", pid: 1, status: "idle", statusUpdatedAt: testNow - minutes(30)),
            entry("same", pid: 2, status: "busy", statusUpdatedAt: testNow - minutes(1)),
        ], alive: [1, 2])

        #expect(sessions.count == 1)
        #expect(sessions.first?.pid == 2)
        #expect(sessions.first?.activity == .working)
    }
}

@Suite struct DesktopSessionTests {
    @Test func buildsDesktopSessionFromRegistry() {
        let sessions = merge([
            entry("d-1", pid: 40, status: "busy", name: "Polish onboarding copy",
                  cwd: "/Users/tester/code/sample-app",
                  startedAt: testNow - minutes(90), statusUpdatedAt: testNow - minutes(2)),
        ], alive: [40])

        #expect(sessions == [
            SessionInfo(
                id: "d-1", name: "Polish onboarding copy", projectPath: "/Users/tester/code/sample-app",
                origin: .desktop, activity: .working, activitySince: testNow - minutes(2),
                startedAt: testNow - minutes(90), pid: 40, transcriptPath: nil, context: nil),
        ])
    }

    @Test func cliRegistryEntryIsATerminalSessionWithRegistryData() {
        let sessions = merge([
            entry("c-1", pid: 41, entrypoint: "cli", status: "busy", name: "Named in terminal",
                  statusUpdatedAt: testNow - minutes(2)),
        ], alive: [41])

        #expect(sessions.map(\.origin) == [.terminal])
        #expect(sessions.map(\.name) == ["Named in terminal"])
        #expect(sessions.map(\.activity) == [.working])
        #expect(sessions.map(\.startedAt) == [testNow - minutes(120)])
    }

    @Test func nameFallsBackToFolderThenPlaceholder() {
        let sessions = merge([
            entry("blank", pid: 1, name: "  ", cwd: "/Users/tester/code/folder-a", statusUpdatedAt: testNow - minutes(1)),
            entry("missing", pid: 2, name: nil, cwd: "/Users/tester/code/folder-b/", statusUpdatedAt: testNow - minutes(2)),
            entry("nothing", pid: 3, name: nil, cwd: nil, statusUpdatedAt: testNow - minutes(3)),
        ], alive: [1, 2, 3])

        #expect(sessions.map(\.name) == ["folder-a", "folder-b", "Untitled session"])
    }

    @Test func mergesBridgeRecordWithSameId() {
        let sessions = merge(
            [entry("d-2", pid: 40, status: "busy", name: "Registry name", cwd: "/Users/tester/code/app",
                   statusUpdatedAt: testNow - minutes(1))],
            [BridgeSessionRecord(
                sessionId: "d-2", pid: 40, cwd: "/Users/tester/code/elsewhere",
                transcriptPath: "/Users/tester/.claude/projects/-Users-tester-code-app/d-2.jsonl",
                lastEvent: "Stop", lastEventAt: testNow - minutes(5))],
            alive: [40])

        #expect(sessions.count == 1)
        let session = sessions[0]
        #expect(session.origin == .desktop)
        #expect(session.name == "Registry name")
        #expect(session.activity == .working)
        #expect(session.projectPath == "/Users/tester/code/app")
        #expect(session.transcriptPath == "/Users/tester/.claude/projects/-Users-tester-code-app/d-2.jsonl")
    }

    @Test func bridgeCwdFillsMissingRegistryCwd() {
        let sessions = merge(
            [entry("d-3", pid: 40, name: nil, cwd: nil)],
            [BridgeSessionRecord(sessionId: "d-3", cwd: "/Users/tester/code/from-hook")],
            alive: [40])

        #expect(sessions.map(\.projectPath) == ["/Users/tester/code/from-hook"])
        #expect(sessions.map(\.name) == ["from-hook"])
    }

    @Test func newerNotificationUpgradesToWaiting() {
        let notifiedAt = testNow - minutes(1)
        let sessions = merge(
            [entry("d-4", pid: 40, status: "busy", statusUpdatedAt: testNow - minutes(3))],
            [BridgeSessionRecord(sessionId: "d-4", lastEvent: "Notification", lastEventAt: notifiedAt,
                                 notificationType: "permission_prompt")],
            alive: [40])

        #expect(sessions.map(\.activity) == [.waitingForInput])
        #expect(sessions.map(\.activitySince) == [notifiedAt])
    }

    @Test func notificationWithoutTypeUpgradesToWaiting() {
        let sessions = merge(
            [entry("d-5", pid: 40, status: "idle", statusUpdatedAt: testNow - minutes(3))],
            [BridgeSessionRecord(sessionId: "d-5", lastEvent: "Notification", lastEventAt: testNow - minutes(1))],
            alive: [40])

        #expect(sessions.map(\.activity) == [.waitingForInput])
    }

    @Test func olderNotificationDoesNotUpgrade() {
        let sessions = merge(
            [entry("d-6", pid: 40, status: "busy", statusUpdatedAt: testNow - minutes(1))],
            [BridgeSessionRecord(sessionId: "d-6", lastEvent: "Notification", lastEventAt: testNow - minutes(3))],
            alive: [40])

        #expect(sessions.map(\.activity) == [.working])
        #expect(sessions.map(\.activitySince) == [testNow - minutes(1)])
    }

    /// Hook `ts` is whole epoch seconds (`date +%s`) while the registry's `statusUpdatedAt` has
    /// milliseconds: a notification stamped in the same second may have happened after the status.
    @Test(arguments: [0.0, 0.001, 0.4, 0.999])
    func notificationInTheSameSecondAsTheStatusUpgrades(statusOffset: Double) {
        let second = testNow - minutes(1)
        let sessions = merge(
            [entry("d-12", pid: 40, status: "busy", statusUpdatedAt: second + statusOffset)],
            [BridgeSessionRecord(sessionId: "d-12", lastEvent: "Notification", lastEventAt: second,
                                 notificationType: "permission_prompt")],
            alive: [40])

        #expect(sessions.map(\.activity) == [.waitingForInput])
        #expect(sessions.map(\.activitySince) == [second])
    }

    @Test(arguments: [1.0, 1.5, 60])
    func notificationFromAnEarlierSecondDoesNotUpgrade(statusOffset: Double) {
        let second = testNow - minutes(2)
        let sessions = merge(
            [entry("d-13", pid: 40, status: "busy", statusUpdatedAt: second + statusOffset)],
            [BridgeSessionRecord(sessionId: "d-13", lastEvent: "Notification", lastEventAt: second,
                                 notificationType: "permission_prompt")],
            alive: [40])

        #expect(sessions.map(\.activity) == [.working])
        #expect(sessions.map(\.activitySince) == [second + statusOffset])
    }

    /// Spec §2.5: approving a permission prompt fires PostToolUse, which ends "needs you" even
    /// when the registry status has not changed since the prompt.
    @Test func postToolUseAfterAPermissionPromptClearsNeedsYou() {
        let promptAt = testNow - minutes(3)
        let registry = [entry("d-14", pid: 40, status: "busy", statusUpdatedAt: promptAt - 5)]
        let waiting = merge(registry, [
            BridgeSessionRecord(sessionId: "d-14", lastEvent: "Notification", lastEventAt: promptAt,
                                notificationType: "permission_prompt"),
        ], alive: [40])
        #expect(waiting.map(\.activity) == [.waitingForInput])

        let approved = merge(registry, [
            BridgeSessionRecord(sessionId: "d-14", lastEvent: "PostToolUse", lastEventAt: promptAt + 20),
        ], alive: [40])
        #expect(approved.map(\.activity) == [.working])

        let terminal = merge([], [
            BridgeSessionRecord(sessionId: "t-14", pid: 41, lastEvent: "PostToolUse", lastEventAt: promptAt + 20),
        ], alive: [41])
        #expect(terminal.map(\.activity) == [.working])
    }

    @Test func idlePromptNotificationDoesNotUpgrade() {
        let sessions = merge(
            [entry("d-7", pid: 40, status: "idle", statusUpdatedAt: testNow - minutes(3))],
            [BridgeSessionRecord(sessionId: "d-7", lastEvent: "Notification", lastEventAt: testNow - minutes(1),
                                 notificationType: "idle_prompt")],
            alive: [40])

        #expect(sessions.map(\.activity) == [.idle])
    }

    @Test func newerNonNotificationEventDoesNotOverrideRegistry() {
        let sessions = merge(
            [entry("d-8", pid: 40, status: "busy", statusUpdatedAt: testNow - minutes(3))],
            [BridgeSessionRecord(sessionId: "d-8", lastEvent: "Stop", lastEventAt: testNow - minutes(1))],
            alive: [40])

        #expect(sessions.map(\.activity) == [.working])
    }

    @Test func notificationUpgradesWhenRegistryTimeIsUnknown() {
        let sessions = merge(
            [entry("d-9", pid: 40, status: "idle", statusUpdatedAt: nil)],
            [BridgeSessionRecord(sessionId: "d-9", lastEvent: "Notification", lastEventAt: testNow - minutes(1))],
            alive: [40])

        #expect(sessions.map(\.activity) == [.waitingForInput])
    }

    @Test func notificationWithoutTimeDoesNotUpgrade() {
        let sessions = merge(
            [entry("d-10", pid: 40, status: "idle")],
            [BridgeSessionRecord(sessionId: "d-10", lastEvent: "Notification")],
            alive: [40])

        #expect(sessions.map(\.activity) == [.idle])
    }

    @Test func registryWinsOverBridgeSessionEnd() {
        let sessions = merge(
            [entry("d-11", pid: 40, status: "busy")],
            [BridgeSessionRecord(sessionId: "d-11", pid: 40, lastEvent: "SessionEnd", lastEventAt: testNow)],
            alive: [40])

        #expect(sessions.map(\.id) == ["d-11"])
        #expect(sessions.map(\.origin) == [.desktop])
    }
}

@Suite struct TerminalSessionTests {
    @Test func buildsTerminalSessionFromBridge() {
        let sessions = merge([], [
            BridgeSessionRecord(
                sessionId: "t-1", pid: 50, cwd: "/Users/tester/code/demo",
                transcriptPath: "/Users/tester/.claude/projects/-Users-tester-code-demo/t-1.jsonl",
                lastEvent: "UserPromptSubmit", lastEventAt: testNow - minutes(4),
                statusLineAt: testNow - minutes(2), contextWindowSize: 200_000,
                contextUsedPercent: 26, modelId: "claude-haiku-4-5"),
        ], alive: [50])

        // The activity dates from the hook event, not the newer status line (1.1 §14.1).
        #expect(sessions == [
            SessionInfo(
                id: "t-1", name: "demo", projectPath: "/Users/tester/code/demo", origin: .terminal,
                activity: .working, activitySince: testNow - minutes(4), startedAt: nil, pid: 50,
                transcriptPath: "/Users/tester/.claude/projects/-Users-tester-code-demo/t-1.jsonl", context: nil),
        ])
    }

    @Test(arguments: [
        ("UserPromptSubmit", nil, SessionActivity.working),
        ("PreToolUse", nil, .working),
        ("PostToolUse", nil, .working),
        ("Stop", nil, .idle),
        ("SessionStart", nil, .idle),
        ("Notification", nil, .waitingForInput),
        ("Notification", "permission_prompt", .waitingForInput),
        ("Notification", "idle_prompt", .idle),
    ] as [(String, String?, SessionActivity)])
    func mapsHookEvents(_ event: String, _ notificationType: String?, _ expected: SessionActivity) {
        let sessions = merge([], [
            BridgeSessionRecord(sessionId: "t-2", pid: 50, lastEvent: event, lastEventAt: testNow,
                                notificationType: notificationType),
        ], alive: [50])

        #expect(sessions.map(\.activity) == [expected])
    }

    @Test func statusLineOnlyRecordIsIdle() {
        let sessions = merge([], [
            BridgeSessionRecord(sessionId: "t-3", pid: 50, statusLineAt: testNow - minutes(1)),
        ], alive: [50])

        #expect(sessions.map(\.activity) == [.idle])
        #expect(sessions.map(\.activitySince) == [testNow - minutes(1)])
    }

    @Test func pidLivenessDecidesVisibility() {
        let sessions = merge([], [
            BridgeSessionRecord(sessionId: "alive", pid: 50, lastEvent: "Stop", lastEventAt: testNow - minutes(600)),
            BridgeSessionRecord(sessionId: "dead", pid: 51, lastEvent: "Stop", lastEventAt: testNow - minutes(1)),
        ], alive: [50])

        #expect(sessions.map(\.id) == ["alive"])
    }

    @Test func withoutPidOnlyRecentRecordsAreShown() {
        let sessions = merge([], [
            BridgeSessionRecord(sessionId: "recent", lastEvent: "Stop", lastEventAt: testNow - minutes(29)),
            BridgeSessionRecord(sessionId: "recent-status", lastEvent: "Stop", lastEventAt: testNow - minutes(90),
                                statusLineAt: testNow - minutes(5)),
            BridgeSessionRecord(sessionId: "old", lastEvent: "Stop", lastEventAt: testNow - minutes(31)),
            BridgeSessionRecord(sessionId: "boundary", lastEvent: "Stop", lastEventAt: testNow - minutes(30)),
            BridgeSessionRecord(sessionId: "timeless", lastEvent: "Stop"),
        ], alive: [])

        #expect(Set(sessions.map(\.id)) == ["recent", "recent-status"])
    }

    @Test func sessionEndDropsRecordEvenWhenPidIsAlive() {
        let sessions = merge([], [
            BridgeSessionRecord(sessionId: "ended", pid: 50, lastEvent: "SessionEnd", lastEventAt: testNow),
            BridgeSessionRecord(sessionId: "ended-no-pid", lastEvent: "SessionEnd", lastEventAt: testNow),
        ], alive: [50])

        #expect(sessions.isEmpty)
    }

    @Test func nameIsFolderOfCwdWithFallback() {
        let sessions = merge([], [
            BridgeSessionRecord(sessionId: "a", pid: 1, cwd: "/Users/tester/code/alpha", lastEventAt: testNow - minutes(1)),
            BridgeSessionRecord(sessionId: "b", pid: 2, cwd: "/Users/tester/code/beta/", lastEventAt: testNow - minutes(2)),
            BridgeSessionRecord(sessionId: "c", pid: 3, cwd: nil, lastEventAt: testNow - minutes(3)),
            BridgeSessionRecord(sessionId: "d", pid: 4, cwd: "/", lastEventAt: testNow - minutes(4)),
        ], alive: [1, 2, 3, 4])

        #expect(sessions.map(\.name) == ["alpha", "beta", "Terminal session", "Terminal session"])
    }

    @Test func bridgeRecordOfExcludedRegistrySessionIsNotShown() {
        let sessions = merge(
            [entry("plugin", pid: 60, entrypoint: "sdk-cli", status: "busy")],
            [BridgeSessionRecord(sessionId: "plugin", pid: 60, lastEvent: "PreToolUse", lastEventAt: testNow)],
            alive: [60])

        #expect(sessions.isEmpty)
    }

    /// A plugin's SDK process whose registry entry already names a newer session id (after a
    /// `/clear` or a fork) still owns its older hook record: same process, so still a plugin session.
    @Test(arguments: ["sdk-ts", "sdk-cli", nil] as [String?])
    func bridgeRecordSharingAPluginPidIsNotShown(_ entrypoint: String?) {
        let sessions = merge(
            [entry("plugin-now", pid: 60, entrypoint: entrypoint, status: "busy")],
            [BridgeSessionRecord(sessionId: "plugin-earlier", pid: 60, cwd: "/Users/tester/code/plugin-worker",
                                 lastEvent: "PreToolUse", lastEventAt: testNow)],
            alive: [60])

        #expect(sessions.isEmpty)
    }

    @Test func bridgeRecordOfDeadRegistryEntryStandsOnItsOwn() {
        let sessions = merge(
            [entry("resumed", pid: 60, status: "busy")],
            [BridgeSessionRecord(sessionId: "resumed", pid: 61, cwd: "/Users/tester/code/demo",
                                 lastEvent: "UserPromptSubmit", lastEventAt: testNow)],
            alive: [61])

        #expect(sessions.map(\.origin) == [.terminal])
        #expect(sessions.map(\.pid) == [61])
    }

    @Test func recordClaimingADesktopSessionPidIsDropped() {
        let sessions = merge(
            [entry("current", pid: 70)],
            [BridgeSessionRecord(sessionId: "cleared-earlier", pid: 70, lastEvent: "Stop", lastEventAt: testNow)],
            alive: [70])

        #expect(sessions.map(\.id) == ["current"])
    }

    @Test func recordsSharingAPidKeepOnlyTheNewest() {
        let sessions = merge([], [
            BridgeSessionRecord(sessionId: "before-clear", pid: 80, lastEvent: "Stop", lastEventAt: testNow - minutes(20)),
            BridgeSessionRecord(sessionId: "after-clear", pid: 80, lastEvent: "SessionStart", lastEventAt: testNow - minutes(2)),
        ], alive: [80])

        #expect(sessions.map(\.id) == ["after-clear"])
    }
}

/// CLI 2.1.281 registers terminal sessions too, named with a slug it derives from the folder
/// (`nameSource: "derived"`): non-ASCII letters dropped, a random suffix added. Spec §2.5 names
/// terminal sessions after the folder, so a derived name is never shown.
@Suite struct RegistryNameTests {
    private let cafe = "/Users/tester/code/hr-e2e café"

    @Test(arguments: ["cli", "claude-desktop"])
    func derivedNameGivesWayToTheFolderName(_ entrypoint: String) {
        let sessions = merge([
            entry("c-1", pid: 41, entrypoint: entrypoint, name: "hr-e2e-caf-59", cwd: cafe, nameSource: "derived"),
        ], alive: [41])

        #expect(sessions.map(\.name) == ["hr-e2e café"])
    }

    @Test func derivedNameWithoutAFolderUsesTheBridgeFolderOrThePlaceholder() {
        let sessions = merge(
            [
                entry("from-hook", pid: 41, entrypoint: "cli", name: "plainapp-82", cwd: nil,
                      statusUpdatedAt: testNow - minutes(1), nameSource: "derived"),
                entry("nowhere", pid: 42, entrypoint: "cli", name: "plainapp-83", cwd: nil,
                      statusUpdatedAt: testNow - minutes(2), nameSource: "derived"),
            ],
            [BridgeSessionRecord(sessionId: "from-hook", pid: 41, cwd: "/Users/tester/code/plainapp")],
            alive: [41, 42])

        #expect(sessions.map(\.name) == ["plainapp", "Untitled session"])
    }

    /// `auto` (Claude's generated title), `user` (renamed) and no source at all are real titles.
    @Test(arguments: ["auto", "user", nil] as [String?])
    func realTitlesAreKept(_ nameSource: String?) {
        let sessions = merge([
            entry("c-2", pid: 41, entrypoint: "cli", name: "Tidy the parser", cwd: cafe, nameSource: nameSource),
        ], alive: [41])

        #expect(sessions.map(\.name) == ["Tidy the parser"])
    }

    /// The entry a zero-prompt `claude` 2.1.281 wrote in a folder named `hr-e2e café`, merged with
    /// its bridge record: one terminal session, named after the folder.
    @Test func cliEntryFromTheRegistryIsNamedAfterItsFolder() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let url = try #require(
            Bundle.module.url(forResource: "registry-cli-derived", withExtension: "json", subdirectory: "Fixtures"))
        try dir.write("51234.json", data: Data(contentsOf: url))
        let registry = try SessionRegistryReader(directory: dir.url).readEntries()
        let id = "66666666-7777-4888-9999-aaaaaaaaaaaa"

        let sessions = merge(
            registry,
            [BridgeSessionRecord(sessionId: id, pid: 51234, cwd: cafe, lastEvent: "SessionStart",
                                 lastEventAt: Date(timeIntervalSince1970: 1_790_250_741))],
            alive: [51234],
            startTimes: [51234: Date(timeIntervalSince1970: 1_790_250_740.3)])

        #expect(sessions.map(\.id) == [id])
        #expect(sessions.map(\.origin) == [.terminal])
        #expect(sessions.map(\.name) == ["hr-e2e café"])
    }
}

/// A crashed or SIGKILLed session leaves its files behind, and its pid may later go to an unrelated
/// process. `kill(pid, 0)` cannot tell; the process's start time can.
@Suite struct PidReuseTests {
    private let procStart = Date(timeIntervalSince1970: 1_790_000_000) // Mon Sep 21 2026, whole seconds

    // MARK: Registry entries with `procStart`

    /// `procStart` is `ps -o lstart`: whole seconds, so the real start lies in the following second.
    @Test(arguments: [0.0, 0.4, 0.999, 1.5, -1.5])
    func registryEntryIsShownWhileItsProcessHoldsThePid(offset: Double) {
        let sessions = merge(
            [entry("d-1", pid: 40, status: "busy", processStartedAt: procStart)],
            alive: [40], startTimes: [40: procStart + offset])

        #expect(sessions.map(\.id) == ["d-1"])
    }

    @Test(arguments: [2.0, 60, 3 * 86_400, -2.5, -3600] as [Double])
    func registryEntryIsHiddenOnceAnotherProcessHoldsThePid(offset: Double) {
        let sessions = merge(
            [entry("d-1", pid: 40, status: "busy", processStartedAt: procStart)],
            alive: [40], startTimes: [40: procStart + offset])

        #expect(sessions.isEmpty)
    }

    /// The audit's fixture: a busy desktop session from Sep 21 whose pid now belongs to a `sleep`.
    @Test func crashedDesktopSessionIsNotShownAsWorking() {
        let crashedAt = Date(timeIntervalSince1970: 1_790_000_000)
        let sessions = merge(
            [entry("crashed", pid: 44011, status: "busy", name: "Crashed session",
                   startedAt: crashedAt + 0.8, statusUpdatedAt: crashedAt + 600, processStartedAt: crashedAt)],
            alive: [44011], startTimes: [44011: testNow - minutes(3)])

        #expect(sessions.isEmpty)
    }

    // MARK: Registry entries without `procStart`

    /// The process wrote the entry, so it started before the entry's newest time.
    @Test(arguments: [-minutes(121), -minutes(60), -minutes(10) + 1])
    func withoutProcStartAProcessOlderThanTheEntryKeepsIt(startOffset: Double) {
        let sessions = merge(
            [entry("d-2", pid: 40, startedAt: testNow - minutes(120), statusUpdatedAt: testNow - minutes(10))],
            alive: [40], startTimes: [40: testNow + startOffset])

        #expect(sessions.map(\.id) == ["d-2"])
    }

    @Test(arguments: [-minutes(10) + 2, -minutes(5), 0])
    func withoutProcStartAProcessNewerThanTheEntryIsAnotherProcess(startOffset: Double) {
        let sessions = merge(
            [entry("d-2", pid: 40, startedAt: testNow - minutes(120), statusUpdatedAt: testNow - minutes(10))],
            alive: [40], startTimes: [40: testNow + startOffset])

        #expect(sessions.isEmpty)
    }

    @Test func withoutAnyTimesLivenessDecides() {
        let sessions = merge(
            [entry("d-3", pid: 40, startedAt: nil, statusUpdatedAt: nil)],
            alive: [40], startTimes: [40: testNow - minutes(1)])

        #expect(sessions.map(\.id) == ["d-3"])
    }

    // MARK: Unknown start times

    /// A probe that cannot tell start times (or a sandbox that will not say) falls back to `kill`.
    @Test func unknownStartTimeFallsBackToLiveness() {
        let registry = [entry("d-4", pid: 40, processStartedAt: procStart)]
        let bridge = [BridgeSessionRecord(sessionId: "t-4", pid: 50, lastEvent: "Stop", lastEventAt: testNow - minutes(600))]

        let unknown = merge(registry, bridge, alive: [40, 50])
        let legacy = SessionMerger.merge(
            registry: registry, bridge: bridge, probe: LivenessOnlyProbe(alive: [40, 50]), now: testNow)

        #expect(Set(unknown.map(\.id)) == ["d-4", "t-4"])
        #expect(Set(legacy.map(\.id)) == ["d-4", "t-4"])
    }

    // MARK: Bridge records

    /// Hook `ts` is whole seconds: the process that wrote it started before `ts + 1 s`.
    @Test(arguments: [-86_400, -1, 0, 0.999, 1.5])
    func bridgeRecordIsShownWhileItsWriterHoldsThePid(offset: Double) {
        let written = testNow - minutes(10)
        let sessions = merge([], [
            BridgeSessionRecord(sessionId: "t-1", pid: 50, cwd: "/Users/tester/code/demo",
                                lastEvent: "Stop", lastEventAt: written),
        ], alive: [50], startTimes: [50: written + offset])

        #expect(sessions.map(\.id) == ["t-1"])
    }

    /// The audit's second case: a SIGKILLed terminal session's files, its pid now a `/bin/sleep`.
    @Test(arguments: [2.0, 60, 86_400])
    func bridgeRecordIsHiddenOnceALaterProcessHoldsThePid(offset: Double) {
        let written = testNow - minutes(10)
        let sessions = merge([], [
            BridgeSessionRecord(sessionId: "t-1", pid: 50, cwd: "/Users/tester/code/hr-e2e café",
                                lastEvent: "Stop", lastEventAt: written),
        ], alive: [50], startTimes: [50: written + offset])

        #expect(sessions.isEmpty)
    }

    /// The newest write counts: a status line refresh after the last hook keeps the session.
    @Test func newerStatusLineVouchesForTheProcess() {
        let sessions = merge([], [
            BridgeSessionRecord(sessionId: "t-2", pid: 50, lastEvent: "Stop", lastEventAt: testNow - minutes(30),
                                statusLineAt: testNow - minutes(1)),
        ], alive: [50], startTimes: [50: testNow - minutes(20)])

        #expect(sessions.map(\.id) == ["t-2"])
    }

    @Test func bridgeRecordWithoutTimesFallsBackToLiveness() {
        let sessions = merge([], [BridgeSessionRecord(sessionId: "t-3", pid: 50)],
                             alive: [50], startTimes: [50: testNow - minutes(1)])

        #expect(sessions.map(\.id) == ["t-3"])
    }

    // MARK: Claims

    /// A plugin entry left behind by a killed SDK process must not hide the terminal session
    /// whose `claude` process was later given the same pid.
    @Test func stalePluginEntryDoesNotClaimAReusedPid() {
        let sessions = merge(
            [entry("plugin", pid: 60, entrypoint: "sdk-cli", status: "busy", processStartedAt: procStart)],
            [BridgeSessionRecord(sessionId: "term", pid: 60, cwd: "/Users/tester/code/demo",
                                 lastEvent: "UserPromptSubmit", lastEventAt: testNow - minutes(1))],
            alive: [60], startTimes: [60: testNow - minutes(5)])

        #expect(sessions.map(\.id) == ["term"])
        #expect(sessions.map(\.origin) == [.terminal])
    }

    /// A ghost registry entry claims nothing; the live session that reused its pid is shown once.
    @Test func ghostRegistryEntryDoesNotClaimAReusedPid() {
        let sessions = merge(
            [entry("crashed", pid: 60, status: "busy", processStartedAt: procStart)],
            [BridgeSessionRecord(sessionId: "term", pid: 60, lastEvent: "Stop", lastEventAt: testNow - minutes(1))],
            alive: [60], startTimes: [60: testNow - minutes(5)])

        #expect(sessions.map(\.id) == ["term"])
    }

    @Test func livePluginEntryStillClaimsItsPid() {
        let sessions = merge(
            [entry("plugin", pid: 60, entrypoint: "sdk-cli", status: "busy", processStartedAt: procStart)],
            [BridgeSessionRecord(sessionId: "plugin-earlier", pid: 60, lastEvent: "PreToolUse",
                                 lastEventAt: testNow - minutes(1))],
            alive: [60], startTimes: [60: procStart + 0.5])

        #expect(sessions.isEmpty)
    }
}

@Suite struct MergeOrderingTests {
    @Test func resultIsSortedForDisplay() {
        let sessions = merge(
            [
                entry("idle-old", pid: 1, status: "idle", statusUpdatedAt: testNow - minutes(50)),
                entry("busy", pid: 2, status: "busy", statusUpdatedAt: testNow - minutes(5)),
                entry("idle-new", pid: 3, status: "idle", statusUpdatedAt: testNow - minutes(1)),
            ],
            [
                BridgeSessionRecord(sessionId: "term-waiting", pid: 4, lastEvent: "Notification",
                                    lastEventAt: testNow - minutes(3)),
                BridgeSessionRecord(sessionId: "term-working", pid: 5, lastEvent: "PreToolUse",
                                    lastEventAt: testNow - minutes(1)),
            ],
            alive: [1, 2, 3, 4, 5])

        #expect(sessions.map(\.id) == ["term-working", "busy", "term-waiting", "idle-new", "idle-old"])
    }

    @Test func emptyInputsGiveNoSessions() {
        #expect(merge(alive: []).isEmpty)
    }
}

/// 1.1 §14.1: a terminal `claude` parked on its startup dialog, notification types, the 1-second rule and waiting
/// episodes that status line writes don't restart.
@Suite struct StaleNeedsYouTests {
    private let launched = testNow - minutes(180)

    @Test func startupDialogIsIdle() {
        let sessions = merge([
            entry("cli-1", pid: 60, entrypoint: "cli", status: "waiting", startedAt: launched,
                  statusUpdatedAt: launched + 7.7, waitingFor: "dialog open", version: "2.1.281"),
        ], alive: [60])

        #expect(sessions.map(\.activity) == [.idle])
        #expect(sessions.map(\.activitySince) == [launched + 7.7])
    }

    @Test func aLaterDialogStillNeedsYou() {
        let sessions = merge([
            entry("cli-2", pid: 61, entrypoint: "cli", status: "waiting", startedAt: launched,
                  statusUpdatedAt: launched + minutes(20), waitingFor: "dialog open"),
            entry("cli-3", pid: 62, entrypoint: "cli", status: "waiting", startedAt: launched,
                  statusUpdatedAt: launched + 5, waitingFor: "permission prompt"),
        ], alive: [61, 62])

        #expect(sessions.map(\.activity) == [.waitingForInput, .waitingForInput])
    }

    /// With the bridge, a blocking dialog opened at launch still reaches "needs you" through its notification.
    @Test func aNewerNeedsYouNotificationStillUpgradesAStartupDialog() {
        let notifiedAt = launched + 30
        let sessions = merge(
            [entry("cli-4", pid: 63, entrypoint: "cli", status: "waiting", startedAt: launched,
                   statusUpdatedAt: launched + 7.7, waitingFor: "dialog open")],
            [BridgeSessionRecord(sessionId: "cli-4", lastEvent: "Notification", lastEventAt: notifiedAt,
                                 notificationType: "permission_prompt")],
            alive: [63])

        #expect(sessions.map(\.activity) == [.waitingForInput])
        #expect(sessions.map(\.activitySince) == [notifiedAt])
    }

    @Test(arguments: ["agent_completed", "auth_success", "idle_prompt", "elicitation_complete", "future_type"])
    func otherNotificationsDontUpgrade(type: String) {
        let sessions = merge(
            [entry("d-20", pid: 64, status: "idle", statusUpdatedAt: testNow - minutes(3))],
            [BridgeSessionRecord(sessionId: "d-20", lastEvent: "Notification", lastEventAt: testNow - minutes(1),
                                 notificationType: type)],
            alive: [64])

        #expect(sessions.map(\.activity) == [.idle])
    }

    /// The question was answered in the notification's own second: an entry that reports waits itself already
    /// says so; one that doesn't keeps 1.0's whole-second tolerance.
    @Test(arguments: [
        ("dialog open", nil, SessionActivity.working),
        (nil, "2.1.281", .working),
        (nil, "2.1.280", .waitingForInput),
        (nil, nil, .waitingForInput),
    ] as [(String?, String?, SessionActivity)])
    func sameSecondAnswer(waitingFor: String?, version: String?, expected: SessionActivity) {
        let second = testNow - minutes(1)
        let sessions = merge(
            [entry("d-21", pid: 65, status: "busy", statusUpdatedAt: second + 0.6, waitingFor: waitingFor,
                   version: version)],
            [BridgeSessionRecord(sessionId: "d-21", lastEvent: "Notification", lastEventAt: second,
                                 notificationType: "permission_prompt")],
            alive: [65])

        #expect(sessions.map(\.activity) == [expected])
    }

    /// A status written in the second before the notification is older even when the registry reports waits.
    @Test func statusBeforeTheNotificationSecondIsOlder() {
        let second = testNow - minutes(1)
        let sessions = merge(
            [entry("d-22", pid: 66, status: "busy", statusUpdatedAt: second - 0.2, version: "2.1.281")],
            [BridgeSessionRecord(sessionId: "d-22", lastEvent: "Notification", lastEventAt: second,
                                 notificationType: "permission_prompt")],
            alive: [66])

        #expect(sessions.map(\.activity) == [.waitingForInput])
    }

    /// Status line writes every few seconds don't move a waiting terminal session's episode.
    @Test func statusLineWritesDontRestartAWait() {
        let notifiedAt = testNow - minutes(10)
        let sessions = merge([], [
            BridgeSessionRecord(sessionId: "t-20", pid: 67, lastEvent: "Notification", lastEventAt: notifiedAt,
                                notificationType: "permission_prompt", statusLineAt: testNow - 2),
        ], alive: [67])

        #expect(sessions.map(\.activity) == [.waitingForInput])
        #expect(sessions.map(\.activitySince) == [notifiedAt])
    }
}

/// 1.1 §14.3: desktop sessions carry the Claude app's own id; terminal ones never do.
@Suite struct DesktopSessionIDTests {
    @Test func desktopEntriesKeepTheHostSessionID() {
        let sessions = merge([
            entry("d-30", pid: 70, entrypoint: "claude-desktop", statusUpdatedAt: testNow - minutes(1),
                  hostSessionId: "local_0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b"),
            entry("c-30", pid: 71, entrypoint: "cli", statusUpdatedAt: testNow - minutes(2), hostSessionId: "local_x"),
            entry("d-31", pid: 72, entrypoint: "claude-desktop", statusUpdatedAt: testNow - minutes(3)),
        ], alive: [70, 71, 72])

        let ids = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.desktopSessionID) })
        #expect(ids == ["d-30": "local_0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b", "c-30": nil, "d-31": nil])
    }

    @Test func bridgeOnlySessionsHaveNone() {
        let sessions = merge([], [
            BridgeSessionRecord(sessionId: "t-30", pid: 73, lastEvent: "Stop", lastEventAt: testNow - minutes(1)),
        ], alive: [73])

        #expect(sessions.map(\.desktopSessionID) == [nil])
    }
}
