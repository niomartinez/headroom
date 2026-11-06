import Foundation
import HeadroomModel
import SessionKit
import Testing
@testable import HeadroomStore

/// Sessions from the registry and the bridge (spec §2.2, §2.5, §3.3).
@Suite struct SnapshotSessionTests {
    @Test func mergesRegistryAndBridgeSessionsSortedForDisplay() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeRegistryEntry(sessionId: "desk-idle", pid: 101, status: "idle", statusUpdatedAt: testNow - 30 * minute)
        try tree.writeRegistryEntry(sessionId: "desk-busy", pid: 102, status: "busy", statusUpdatedAt: testNow - 3 * minute)
        try tree.writeRegistryEntry(sessionId: "desk-wait", pid: 103, status: "waiting_for_permission", statusUpdatedAt: testNow - minute)
        try tree.writeRegistryEntry(sessionId: "plugin", pid: 104, entrypoint: "sdk-cli", status: "busy")
        try tree.writeRegistryEntry(sessionId: "desk-dead", pid: 105, status: "busy")
        try tree.writeBridgeHook(sessionId: "term-busy", pid: 201, event: "PreToolUse", at: testNow - 20 * second)

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101, 102, 103, 104, 201]))
            .build(access: .full, now: testNow)

        #expect(snapshot.sessions.map(\.id) == ["term-busy", "desk-busy", "desk-wait", "desk-idle"])
        #expect(snapshot.sessions.map(\.activity) == [.working, .working, .waitingForInput, .idle])
        #expect(snapshot.sessions.first?.origin == .terminal)
        #expect(snapshot.sessions.first?.name == "terminal-tool")
        #expect(snapshot.issues.isEmpty)
    }

    @Test func aSessionInBothSourcesIsShownOnce() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeRegistryEntry(sessionId: "shared", pid: 300, entrypoint: "cli", status: "busy", name: "Tidy the parser")
        try tree.writeBridgeHook(sessionId: "shared", pid: 300, event: "UserPromptSubmit", at: testNow - minute)
        try tree.writeBridgeStatusLine(
            sessionId: "shared", pid: 300, at: testNow - minute, model: "claude-haiku-4-5", contextWindowSize: 200_000)

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [300]))
            .build(access: .full, now: testNow)

        #expect(snapshot.sessions.count == 1)
        #expect(snapshot.sessions.first?.name == "Tidy the parser")
        #expect(snapshot.sessions.first?.origin == .terminal)
    }

    @Test func unreadableRegistryIsAnIssueAndBridgeSessionsRemain() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeRegistryEntry(sessionId: "desk-1", pid: 101, status: "busy")
        try tree.writeBridgeHook(sessionId: "term-1", pid: 201, event: "Stop", at: testNow - minute)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: tree.paths.sessionsDirectory.path)

        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101, 201]))
        let snapshot = builder.build(access: .full, now: testNow)

        #expect(snapshot.issues == [.sessionRegistryUnreadable])
        #expect(snapshot.sessions.map(\.id) == ["term-1"])

        // Once it is readable again the issue goes away.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tree.paths.sessionsDirectory.path)
        let recovered = builder.build(access: .full, now: testNow + 2 * second)
        #expect(recovered.issues.isEmpty)
        #expect(Set(recovered.sessions.map(\.id)) == ["desk-1", "term-1"])
    }

    @Test func missingRegistryIsNotAnIssue() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeBridgeHook(sessionId: "term-1", pid: 201, event: "Stop", at: testNow - minute)

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [201]))
            .build(access: .full, now: testNow)

        #expect(snapshot.issues.isEmpty)
        #expect(snapshot.sessions.map(\.id) == ["term-1"])
    }

    @Test func livenessIsCheckedOnEveryBuild() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeRegistryEntry(sessionId: "desk-1", pid: 101, status: "busy")
        let probe = MutableProbe(alive: [101])
        let builder = SnapshotBuilder(paths: tree.paths, probe: probe)

        #expect(builder.build(access: .full, now: testNow).sessions.count == 1)
        probe.set(alive: [])
        #expect(builder.build(access: .full, now: testNow + 2 * second).sessions.isEmpty)
    }

    @Test func registryChangesAreSeen() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        let entry = try tree.writeRegistryEntry(sessionId: "desk-1", pid: 101, status: "busy", statusUpdatedAt: testNow - minute)
        try tree.setModified(entry, testNow - minute)
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101, 102]))
        #expect(builder.build(access: .full, now: testNow).sessions.first?.activity == .working)

        try tree.writeRegistryEntry(sessionId: "desk-1", pid: 101, status: "idle", statusUpdatedAt: testNow)
        try tree.writeRegistryEntry(sessionId: "desk-2", pid: 102, status: "idle", statusUpdatedAt: testNow)
        let snapshot = builder.build(access: .full, now: testNow + 2 * second)

        #expect(snapshot.sessions.map(\.activity) == [.idle, .idle])
        #expect(snapshot.sessions.count == 2)
    }

    // MARK: Reused pids (F19)

    /// A session that crashed or was killed leaves its registry entry and bridge records behind. A later,
    /// unrelated process that was given the same pid is alive, but started after the session did (registry
    /// `procStart`) or after the session last wrote (bridge `ts`, registry times): it is not shown, and not
    /// counted next to the pill's dot.
    @Test func aLivePidThatStartedLaterIsNotTheSession() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        let sessionStart = testNow - 2 * hour
        try tree.writeRegistryEntry(sessionId: "desk-live", pid: 101, status: "busy", startedAt: sessionStart, procStart: sessionStart)
        try tree.writeRegistryEntry(sessionId: "desk-reused", pid: 102, status: "busy", startedAt: sessionStart, procStart: sessionStart)
        try tree.writeRegistryEntry(
            sessionId: "desk-reused-no-procstart", pid: 103, status: "waiting_for_permission",
            startedAt: sessionStart, statusUpdatedAt: testNow - 10 * minute
        )
        try tree.writeBridgeHook(sessionId: "term-live", pid: 201, event: "PreToolUse", at: testNow - minute)
        try tree.writeBridgeHook(sessionId: "term-reused", pid: 202, event: "UserPromptSubmit", at: testNow - 30 * minute)
        let probe = FakeProcessProbe(alive: [101, 102, 103, 201, 202], startTimes: [
            101: sessionStart,
            102: testNow - hour,
            103: testNow - 5 * minute,
            201: testNow - 3 * hour,
            202: testNow - 5 * minute,
        ])

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: probe).build(access: .full, now: testNow)

        #expect(Set(snapshot.sessions.map(\.id)) == ["desk-live", "term-live"])
        #expect(snapshot.activeCount == 2)
        #expect(snapshot.waitingCount == 0)
    }

    /// Without a start time for the pid, liveness alone decides, as before.
    @Test func anUnknownStartTimeKeepsTheSession() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeRegistryEntry(sessionId: "desk-1", pid: 101, status: "busy", procStart: testNow - 2 * hour)
        try tree.writeBridgeHook(sessionId: "term-1", pid: 201, event: "PreToolUse", at: testNow - minute)

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101, 201]))
            .build(access: .full, now: testNow)

        #expect(Set(snapshot.sessions.map(\.id)) == ["desk-1", "term-1"])
        #expect(snapshot.activeCount == 2)
    }

    /// The session's process exits and its pid goes to a new process between two builds.
    @Test func aPidReusedBetweenBuildsDropsTheSession() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        let sessionStart = testNow - 2 * hour
        try tree.writeRegistryEntry(
            sessionId: "desk-1", pid: 101, status: "busy", name: "Tidy the parser", nameSource: "auto",
            startedAt: sessionStart, procStart: sessionStart
        )
        let probe = MutableProbe(alive: [101], startTimes: [101: sessionStart])
        let builder = SnapshotBuilder(paths: tree.paths, probe: probe)
        let first = builder.build(access: .full, now: testNow)
        #expect(first.sessions.map(\.name) == ["Tidy the parser"])
        #expect(first.activeCount == 1)

        probe.set(startTimes: [101: testNow + second])
        let afterReuse = builder.build(access: .full, now: testNow + 2 * second)

        #expect(afterReuse.sessions.isEmpty)
        #expect(afterReuse.activeCount == 0)
    }

    /// 1.1 §14.11: idle between turns with a background task or agent still running counts as working.
    @Test func backgroundWorkKeepsAnIdleSessionWorking() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeRegistryEntry(sessionId: "bg-shell", pid: 101, status: "idle")
        try tree.writeRegistryEntry(sessionId: "bg-agent", pid: 102, status: "idle")
        try tree.writeRegistryEntry(sessionId: "waiting", pid: 103, status: "waiting_for_permission")
        try tree.writeRegistryEntry(sessionId: "done-agent", pid: 104, status: "idle")
        try tree.writeRegistryEntry(sessionId: "plain", pid: 105, status: "idle")
        for id in ["bg-agent", "done-agent"] {
            let transcript = try tree.writeTranscript(sessionId: id, usages: [])
            let reason = id == "bg-agent" ? "tool_use" : "end_turn"
            try tree.write(
                #"{"type":"assistant","message":{"content":[{"type":"text"}],"stop_reason":"\#(reason)"}}"# + "\n",
                to: transcript.deletingPathExtension().appendingPathComponent("subagents/agent-a1.jsonl"),
                modified: testNow - minute
            )
        }

        let probe = FakeProcessProbe(alive: [101, 102, 103, 104, 105], shells: [101, 103])
        let snapshot = SnapshotBuilder(paths: tree.paths, probe: probe).build(access: .full, now: testNow)
        let activity = Dictionary(uniqueKeysWithValues: snapshot.sessions.map { ($0.id, $0.activity) })

        #expect(activity == [
            "bg-shell": .working, "bg-agent": .working, "waiting": .waitingForInput, "done-agent": .idle, "plain": .idle,
        ])
    }
}

/// A probe whose live pids, and their processes' start times, change during a test.
final class MutableProbe: ProcessProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var alive: Set<Int32>
    private var startTimes: [Int32: Date]

    init(alive: Set<Int32>, startTimes: [Int32: Date] = [:]) {
        self.alive = alive
        self.startTimes = startTimes
    }

    func set(alive: Set<Int32>) {
        lock.withLock { self.alive = alive }
    }

    func set(startTimes: [Int32: Date]) {
        lock.withLock { self.startTimes = startTimes }
    }

    func isAlive(pid: Int32) -> Bool {
        lock.withLock { alive.contains(pid) }
    }

    func startTime(pid: Int32) -> Date? {
        lock.withLock { alive.contains(pid) ? startTimes[pid] : nil }
    }
}
