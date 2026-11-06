#if HEADROOM_COPILOT_CLI
import Foundation
import HeadroomModel
import Testing
@testable import SessionKit

/// Copilot CLI sessions from the Copilot bridge's records (1.1 §4.9): the activity table, liveness through
/// `logs/process-<epochMs>-<pid>.log`, the 30-minute rule without one, naming and ids.
@Suite("CopilotSessionReader")
struct CopilotSessionReaderTests {
    static let sessionID = "5d3f8a2c-7b1e-4c9d-a6f0-2e8b4c1d9a7f"
    static let otherID = "9e8d7c6b-5a49-4382-a716-f5e4d3c2b1a0"

    /// A temp `~/.copilot` with the bridge's `headroom/sessions/` and Copilot CLI's `logs/`.
    struct Home {
        let temp: TempDirectory
        var paths: CopilotPaths { CopilotPaths(copilotDirectory: temp.url) }

        init() throws {
            temp = try TempDirectory()
            try FileManager.default.createDirectory(at: paths.bridgeSessionsDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: paths.logsDirectory, withIntermediateDirectories: true)
        }

        /// Writes a record as the bridge does.
        func record(
            _ id: String = sessionID,
            ts: Date = testNow.addingTimeInterval(-60),
            event: String = "userPromptSubmitted",
            cwd: String = "/Users/me/code/app",
            notificationType: String = "",
            pids: [(Int32, String)] = [(4242, "copilot")],
            fileName: String? = nil
        ) throws {
            let pidList = pids.map { "[\($0.0),\"\($0.1)\"]" }.joined(separator: ",")
            let json = #"{"v":1,"ts":\#(Int(ts.timeIntervalSince1970)),"event":"\#(event)","session_id":"\#(id)","cwd":"\#(cwd)","notification_type":"\#(notificationType)","pids":[\#(pidList)]}"#
            try Data(json.utf8).write(to: paths.bridgeSessionsDirectory.appendingPathComponent(fileName ?? "\(id).hook.json"))
        }

        /// Creates Copilot CLI's log for a process that started at `started`.
        func log(pid: Int32, started: Date) throws {
            let name = "process-\(Int64((started.timeIntervalSince1970 * 1000).rounded()))-\(pid).log"
            try Data("synthetic\n".utf8).write(to: paths.logsDirectory.appendingPathComponent(name))
        }

        func reader(_ probe: any ProcessProbing) -> CopilotSessionReader {
            CopilotSessionReader(copilotHome: temp.url, probe: probe)
        }
    }

    /// The Copilot process in most tests: pid 4242, started an hour before `testNow`.
    let copilotStart = testNow.addingTimeInterval(-3600)
    var liveCopilot: FakeProcessProbe { FakeProcessProbe(alive: [4242], startTimes: [4242: copilotStart]) }

    // MARK: - Sessions

    @Test func aLiveSessionBecomesACopilotSessionInfo() throws {
        let home = try Home()
        defer { home.temp.remove() }
        try home.record()
        try home.log(pid: 4242, started: copilotStart.addingTimeInterval(0.4))

        let sessions = home.reader(liveCopilot).readSessions(now: testNow)

        #expect(sessions == [
            SessionInfo(
                id: "copilot:\(Self.sessionID)",
                name: "app",
                projectPath: "/Users/me/code/app",
                origin: .terminal,
                activity: .working,
                activitySince: testNow.addingTimeInterval(-60),
                startedAt: nil,
                pid: 4242,
                transcriptPath: nil,
                context: nil,
                tool: .copilot
            ),
        ])
    }

    @Test func readsTheBridgesRecordFormat() throws {
        let home = try Home()
        defer { home.temp.remove() }
        let fixture = try #require(Bundle.module.url(forResource: "copilot-record-notification", withExtension: "json", subdirectory: "Fixtures"))
        try FileManager.default.copyItem(at: fixture, to: home.paths.bridgeSessionsDirectory.appendingPathComponent("\(Self.sessionID).hook.json"))

        let records = home.reader(liveCopilot).readRecords()
        #expect(records == [
            CopilotSessionRecord(
                sessionId: Self.sessionID,
                writtenAt: Date(timeIntervalSince1970: 1_790_250_200),
                event: "notification",
                cwd: "/Users/me/code/app",
                notificationType: "permission_prompt",
                ancestors: [.init(pid: 12345, name: "copilot")]
            ),
        ])
    }

    @Test(arguments: [
        ("sessionStart", "", SessionActivity.idle),
        ("userPromptSubmitted", "", .working),
        ("postToolUse", "", .working),
        ("notification", "permission_prompt", .waitingForInput),
        ("notification", "elicitation_dialog", .waitingForInput),
        // 1.1 §14.1: the same needs-you types as Claude Code's, and an answered elicitation carries on.
        ("notification", "elicitation_url_dialog", .waitingForInput),
        ("notification", "agent_needs_input", .waitingForInput),
        ("notification", "elicitation_complete", .working),
        ("notification", "elicitation_response", .working),
        ("notification", "agent_completed", .idle),
        ("notification", "agent_idle", .idle),
        ("notification", "", .idle),
        ("agentStop", "", .idle),
        ("errorOccurred", "", .idle),
        ("somethingNew", "", .idle),
    ])
    func activityFollowsTheNewestEvent(event: String, notificationType: String, expected: SessionActivity) throws {
        let home = try Home()
        defer { home.temp.remove() }
        try home.record(event: event, notificationType: notificationType)
        try home.log(pid: 4242, started: copilotStart)
        #expect(home.reader(liveCopilot).readSessions(now: testNow).map(\.activity) == [expected])
    }

    @Test func sessionEndIsNeverShown() throws {
        let home = try Home()
        defer { home.temp.remove() }
        try home.record(event: "sessionEnd")
        try home.log(pid: 4242, started: copilotStart)
        #expect(home.reader(liveCopilot).readSessions(now: testNow).isEmpty)
    }

    @Test func completedSessionSurvivesProcessExitAndExpires() throws {
        let home = try Home()
        defer { home.temp.remove() }
        try home.log(pid: 4242, started: copilotStart)
        try home.record(ts: testNow, event: "sessionCompleted")
        let reader = home.reader(FakeProcessProbe())
        let session = try #require(reader.readSessions(now: testNow.addingTimeInterval(2)).first)
        #expect(session.id == "copilot:\(Self.sessionID)")
        #expect(session.activity == .idle)
        #expect(session.pid == nil)
        #expect(reader.readSessions(now: testNow.addingTimeInterval(30 * 60)).isEmpty)
    }

    @Test func nameFallsBackWithoutAFolder() throws {
        let home = try Home()
        defer { home.temp.remove() }
        try home.record(cwd: "")
        try home.log(pid: 4242, started: copilotStart)
        let session = try #require(home.reader(liveCopilot).readSessions(now: testNow).first)
        #expect(session.name == "Terminal session")
        #expect(session.projectPath == nil)
    }

    // MARK: - Liveness through logs

    @Test func deadCopilotProcessHidesTheSession() throws {
        // A crashed session skips sessionEnd; its log names the process, which is gone.
        let home = try Home()
        defer { home.temp.remove() }
        try home.record(ts: testNow.addingTimeInterval(-5))
        try home.log(pid: 4242, started: copilotStart)
        #expect(home.reader(FakeProcessProbe()).readSessions(now: testNow).isEmpty)
    }

    @Test func reusedPidHidesTheSession() throws {
        // The only log for pid 4242 is older than the process holding the pid now: another program got it.
        let home = try Home()
        defer { home.temp.remove() }
        try home.record(ts: testNow.addingTimeInterval(-5))
        try home.log(pid: 4242, started: copilotStart.addingTimeInterval(-600))
        #expect(home.reader(liveCopilot).readSessions(now: testNow).isEmpty)
    }

    @Test func processStartedAfterTheRecordDidntWriteIt() throws {
        // A later Copilot CLI got the pid (with its own log): the record is from before it started.
        let home = try Home()
        defer { home.temp.remove() }
        try home.record(ts: copilotStart.addingTimeInterval(-60))
        try home.log(pid: 4242, started: copilotStart)
        #expect(home.reader(liveCopilot).readSessions(now: testNow).isEmpty)
    }

    @Test func aLogStartedAfterTheProcessStillMatches() throws {
        // Copilot CLI may open its log a few seconds after it starts.
        let home = try Home()
        defer { home.temp.remove() }
        try home.record()
        try home.log(pid: 4242, started: copilotStart.addingTimeInterval(5))
        #expect(home.reader(liveCopilot).readSessions(now: testNow).map(\.pid) == [4242])
    }

    @Test func theFirstAncestorWithALogIsTheCopilotProcess() throws {
        let home = try Home()
        defer { home.temp.remove() }
        try home.record(pids: [(5000, "node"), (4242, "copilot"), (300, "zsh")])
        try home.log(pid: 4242, started: copilotStart)
        let probe = FakeProcessProbe(
            alive: [5000, 4242, 300], startTimes: [5000: copilotStart, 4242: copilotStart, 300: copilotStart.addingTimeInterval(-60)]
        )
        #expect(home.reader(probe).readSessions(now: testNow).map(\.pid) == [4242])
    }

    @Test func liveCopilotKeepsAnOldIdleSessionShown() throws {
        let home = try Home()
        defer { home.temp.remove() }
        try home.record(ts: testNow.addingTimeInterval(-3000), event: "agentStop")
        try home.log(pid: 4242, started: copilotStart)
        #expect(home.reader(liveCopilot).readSessions(now: testNow).map(\.activity) == [.idle])
    }

    @Test func probeWithoutStartTimesTrustsALivePidWithALog() throws {
        let home = try Home()
        defer { home.temp.remove() }
        try home.record()
        try home.log(pid: 4242, started: copilotStart)
        #expect(home.reader(LivenessOnlyProbe(alive: [4242])).readSessions(now: testNow).map(\.pid) == [4242])
    }

    // MARK: - Without a log: 30 minutes

    @Test(arguments: [(29.0, true), (31.0, false)])
    func withoutALogTheRecordShowsForThirtyMinutes(minutesAgo: Double, shown: Bool) throws {
        let home = try Home()
        defer { home.temp.remove() }
        try home.record(ts: testNow.addingTimeInterval(-minutes(minutesAgo)))
        let sessions = home.reader(liveCopilot).readSessions(now: testNow)
        #expect(sessions.count == (shown ? 1 : 0))
        #expect(sessions.first?.pid == nil)
    }

    @Test func missingLogsFolderFallsBackToThirtyMinutes() throws {
        let home = try Home()
        defer { home.temp.remove() }
        try FileManager.default.removeItem(at: home.paths.logsDirectory)
        try home.record(ts: testNow.addingTimeInterval(-minutes(10)))
        #expect(home.reader(liveCopilot).readSessions(now: testNow).map(\.id) == ["copilot:\(Self.sessionID)"])
    }

    // MARK: - Several records

    @Test func oneSessionPerCopilotProcess() throws {
        // `/new` in the same Copilot CLI leaves the earlier session's record behind.
        let home = try Home()
        defer { home.temp.remove() }
        try home.record(Self.sessionID, ts: testNow.addingTimeInterval(-600), event: "agentStop")
        try home.record(Self.otherID, ts: testNow.addingTimeInterval(-60))
        try home.log(pid: 4242, started: copilotStart)
        #expect(home.reader(liveCopilot).readSessions(now: testNow).map(\.id) == ["copilot:\(Self.otherID)"])
    }

    @Test func separateProcessesAreSeparateSessionsSortedForDisplay() throws {
        let home = try Home()
        defer { home.temp.remove() }
        try home.record(Self.sessionID, ts: testNow.addingTimeInterval(-60), event: "agentStop", cwd: "/Users/me/code/one")
        try home.record(Self.otherID, ts: testNow.addingTimeInterval(-600), cwd: "/Users/me/code/two", pids: [(4343, "copilot")])
        try home.log(pid: 4242, started: copilotStart)
        try home.log(pid: 4343, started: copilotStart)
        let probe = FakeProcessProbe(alive: [4242, 4343], startTimes: [4242: copilotStart, 4343: copilotStart])
        let sessions = home.reader(probe).readSessions(now: testNow)
        #expect(sessions.map(\.name) == ["two", "one"])
        #expect(sessions.map(\.activity) == [.working, .idle])
    }

    @Test func newestRecordWinsForOneSessionID() throws {
        let home = try Home()
        defer { home.temp.remove() }
        try home.record(ts: testNow.addingTimeInterval(-60), event: "postToolUse")
        try home.record(ts: testNow.addingTimeInterval(-120), event: "agentStop", fileName: "copy.hook.json")
        try home.log(pid: 4242, started: copilotStart)
        #expect(home.reader(liveCopilot).readSessions(now: testNow).map(\.activity) == [.working])
    }

    @Test func skipsTempFilesJunkAndUnsafeIDs() throws {
        let home = try Home()
        defer { home.temp.remove() }
        let directory = home.paths.bridgeSessionsDirectory
        try home.record(Self.sessionID, fileName: ".\(Self.sessionID).hook.json.99.tmp")
        try Data("{ not json".utf8).write(to: directory.appendingPathComponent("junk.hook.json"))
        try Data(#"{"v":1}"#.utf8).write(to: directory.appendingPathComponent("other.statusline.json"))
        try home.record("../../evil", fileName: "evil.hook.json")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("dir.hook.json"), withIntermediateDirectories: true)
        #expect(home.reader(liveCopilot).readRecords().isEmpty)
    }

    @Test func fileNameIsTheFallbackID() throws {
        let home = try Home()
        defer { home.temp.remove() }
        try Data(#"{"v":1,"ts":1790251140,"event":"agentStop","cwd":"/Users/me/code/app"}"#.utf8)
            .write(to: home.paths.bridgeSessionsDirectory.appendingPathComponent("\(Self.otherID).hook.json"))
        #expect(home.reader(liveCopilot).readSessions(now: testNow).map(\.id) == ["copilot:\(Self.otherID)"])
    }

    @Test func missingRecordsFolderReadsAsNoSessions() throws {
        let temp = try TempDirectory()
        defer { temp.remove() }
        #expect(CopilotSessionReader(copilotHome: temp.url, probe: liveCopilot).readSessions(now: testNow).isEmpty)
    }

    // MARK: - Log names

    @Test func processLogNames() {
        let parsed = CopilotSessionReader.processLog("process-1790250000123-4242.log")
        #expect(parsed?.0 == Date(timeIntervalSince1970: 1_790_250_000.123))
        #expect(parsed?.1 == 4242)
        for name in [
            "process-1790250000123-4242.txt", "process--4242.log", "process-1790250000123-.log", "process-12-34-56.log",
            "process-abc-4242.log", "process-1790250000123-0.log", "session-1790250000123-4242.log", "process-.log",
            "process-1790250000123-99999999999.log",
        ] {
            #expect(CopilotSessionReader.processLog(name) == nil, "\(name)")
        }
    }

    // MARK: - Allowlist (1.1 §4.9)

    @Test func copilotSourcesNeverNameFilesHeadroomMustNotOpen() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources", isDirectory: true)
        let files = [
            "SessionKit/CopilotSessionReader.swift", "SessionKit/CopilotSessionRecord.swift",
            "SetupKit/CopilotBridgeScript.swift", "SetupKit/CopilotBridgeHooks.swift", "SetupKit/CopilotBridgeInstaller.swift",
        ]
        for file in files {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            for forbidden in ["config.json", "settings.json", "session-state", "session-store", ".sqlite", "auth"] {
                #expect(!text.contains(forbidden), "\(file) mentions \(forbidden)")
            }
        }
    }
}
#endif
