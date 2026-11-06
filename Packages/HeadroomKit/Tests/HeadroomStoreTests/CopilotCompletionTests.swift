#if HEADROOM_COPILOT_CLI
import Foundation
import HeadroomModel
import SessionKit
import Testing
@testable import HeadroomStore

@Suite struct CopilotCompletionTests {
    @Test func completedRecordProducesOneFinishedMomentAfterProcessExit() throws {
        let fixture = try FixtureTree()
        defer { fixture.remove() }
        let home = fixture.root.appendingPathComponent("copilot")
        let paths = CopilotPaths(copilotDirectory: home)
        try FileManager.default.createDirectory(at: paths.bridgeSessionsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.logsDirectory, withIntermediateDirectories: true)
        let started = testNow.addingTimeInterval(-60)
        let log = "process-\(Int(started.timeIntervalSince1970 * 1000))-4242.log"
        try Data().write(to: paths.logsDirectory.appendingPathComponent(log))
        func write(_ event: String, at time: Date) throws {
            let data = try JSONSerialization.data(withJSONObject: [
                "v": 1, "session_id": "synthetic-finish", "event": event,
                "ts": time.timeIntervalSince1970, "cwd": "/example/project", "pids": [[4242, "copilot"]],
            ])
            try data.write(to: paths.bridgeSessionsDirectory.appendingPathComponent("synthetic-finish.hook.json"))
        }
        func snapshot(_ sessions: [SessionInfo], at time: Date) -> HeadroomSnapshot {
            HeadroomSnapshot(plan: .empty, sessions: sessions, terminalBridgeConnected: false,
                             issues: [], generatedAt: time, copilot: .copilotSessionsOnly)
        }
        try write("userPromptSubmitted", at: testNow.addingTimeInterval(-10))
        let live = CopilotSessionReader(copilotHome: home, probe: FakeProcessProbe(alive: [4242], startTimes: [4242: started]))
        let before = snapshot(live.readSessions(now: testNow.addingTimeInterval(-2)), at: testNow.addingTimeInterval(-2))
        #expect(before.sessions.first?.activity == .working)

        try write("sessionCompleted", at: testNow)
        let ended = CopilotSessionReader(copilotHome: home, probe: FakeProcessProbe())
        let after = snapshot(ended.readSessions(now: testNow), at: testNow)
        #expect(MomentDetector.moments(previous: before, current: after) == [
            .sessionFinished(sessionID: "copilot:synthetic-finish", name: "project"),
        ])
        let next = snapshot(ended.readSessions(now: testNow.addingTimeInterval(2)), at: testNow.addingTimeInterval(2))
        #expect(MomentDetector.moments(previous: after, current: next).isEmpty)
    }
}
#endif
