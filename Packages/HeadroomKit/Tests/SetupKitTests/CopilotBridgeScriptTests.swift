#if HEADROOM_COPILOT_CLI
import Foundation
import HeadroomModel
import Testing
@testable import SetupKit

/// `~/.copilot/headroom/bridge.sh` (1.1 §4.9), run with `HOME` set to a temp folder and synthetic payloads in
/// Copilot CLI's shapes: it always exits 0, prints nothing, keeps only ids, folders, event names and notification
/// types, and does nothing once Headroom is uninstalled.
@Suite("Copilot bridge.sh")
struct CopilotBridgeScriptTests {
    // MARK: - Records

    @Test(arguments: copilotEventFixtures.map(\.event))
    func eachEventWritesAValidRecord(event: String) throws {
        let sandbox = try Sandbox()
        let fixture = try #require(copilotEventFixtures.first { $0.event == event }).fixture
        let before = Int(Date().timeIntervalSince1970)
        let result = try runCopilotBridge(event: event, fixture: fixture, in: sandbox)
        let after = Int(Date().timeIntervalSince1970)

        #expect(result.status == 0)
        #expect(result.stdout == "")
        #expect(result.stderr == "")
        let record = try sandbox.copilotRecord()
        #expect(Set(record.keys) == ["v", "ts", "event", "session_id", "cwd", "notification_type", "pids"])
        #expect(record["v"] as? Int == 1)
        let ts = try #require(record["ts"] as? Int)
        #expect(ts >= before && ts <= after)
        #expect(record["event"] as? String == event)
        #expect(record["session_id"] as? String == copilotSessionID)
        // Notification payloads carry no cwd (see notificationKeepsTheSessionsFolder).
        #expect(record["cwd"] as? String == (event == "notification" ? "" : "/Users/me/code/app"))
        #expect(record["notification_type"] as? String == (event == "notification" ? "permission_prompt" : ""))
        // Run straight from this test process: the bridge's parent is this process.
        let pids = try #require(record["pids"] as? [[Any]])
        #expect(!pids.isEmpty && pids.count <= 6)
        #expect(pids.first?.first as? Int == Int(ProcessInfo.processInfo.processIdentifier))
    }

    @Test func elicitationDialogIsKept() throws {
        let sandbox = try Sandbox()
        try runCopilotBridge(event: "notification", fixture: "copilot-notification-elicitation.json", in: sandbox)
        #expect(try sandbox.copilotRecord()["notification_type"] as? String == "elicitation_dialog")
    }

    @Test func notificationKeepsTheSessionsFolder() throws {
        // Notification payloads carry no cwd: the folder from the session's earlier record stays.
        let sandbox = try Sandbox()
        try runCopilotBridge(event: "userPromptSubmitted", fixture: "copilot-userPromptSubmitted.json", in: sandbox)
        try runCopilotBridge(event: "notification", fixture: "copilot-notification-permission.json", in: sandbox)
        let record = try sandbox.copilotRecord()
        #expect(record["event"] as? String == "notification")
        #expect(record["cwd"] as? String == "/Users/me/code/app")
    }

    @Test func notificationWithoutAnEarlierRecordHasNoFolder() throws {
        let sandbox = try Sandbox()
        try runCopilotBridge(event: "notification", fixture: "copilot-notification-permission.json", in: sandbox)
        #expect(try sandbox.copilotRecord()["cwd"] as? String == "")
    }

    @Test func snakeCasePayloadsWork() throws {
        let sandbox = try Sandbox()
        let result = try runCopilotBridge(event: "notification", fixture: "copilot-snake-notification.json", in: sandbox)
        #expect(result.status == 0)
        let record = try sandbox.copilotRecord()
        #expect(record["session_id"] as? String == copilotSessionID)
        #expect(record["notification_type"] as? String == "permission_prompt")
        #expect(record["cwd"] as? String == "/Users/me/code/app")
    }

    @Test func withoutAnEventArgumentThePayloadNamesIt() throws {
        let sandbox = try Sandbox()
        try runCopilotBridge(event: nil, stdin: try fixtureText("copilot-snake-notification.json"), in: sandbox)
        #expect(try sandbox.copilotRecord()["event"] as? String == "notification")
    }

    @Test func escapedValuesRoundTrip() throws {
        let sandbox = try Sandbox()
        let cwd = #"/Users/me/code/"quoted" \ café 🚀"#
        let payload = #"{"cwd":\#(try jsonText(cwd)),"prompt":"x","sessionId":"\#(copilotSessionID)","timestamp":1}"#
        try runCopilotBridge(event: "userPromptSubmitted", stdin: payload, in: sandbox)
        #expect(try sandbox.copilotRecord()["cwd"] as? String == cwd)
    }

    // MARK: - Privacy

    @Test func promptTextNeverReachesAnyFile() throws {
        let sandbox = try Sandbox()
        for (event, fixture) in copilotEventFixtures {
            try runCopilotBridge(event: event, fixture: fixture, in: sandbox)
            #expect(!sandbox.anyFileContains(copilotPromptMarker), "\(event)")
        }
        for (event, fixture) in [
            ("notification", "copilot-notification-elicitation.json"), ("notification", "copilot-snake-notification.json"),
        ] {
            try runCopilotBridge(event: event, fixture: fixture, in: sandbox)
            #expect(!sandbox.anyFileContains(copilotPromptMarker), "\(fixture)")
        }
        #expect(sandbox.copilotRecordExists())
    }

    // MARK: - sessionEnd and pruning

    @Test func completionSurvivesImmediateSessionEnd() throws {
        let sandbox = try Sandbox()
        try runCopilotBridge(event: "userPromptSubmitted", fixture: "copilot-userPromptSubmitted.json", in: sandbox)
        try runCopilotBridge(event: "agentStop", fixture: "copilot-agentStop.json", in: sandbox)
        let payload = #"{"reason":"complete","sessionId":"\#(copilotSessionID)","cwd":"/Users/me/code/app"}"#
        try runCopilotBridge(event: "sessionEnd", stdin: payload, in: sandbox)
        #expect(sandbox.copilotRecordExists(), "Copilot desktop ends its session before the next Headroom poll")
        if sandbox.copilotRecordExists() {
            #expect(try sandbox.copilotRecord()["event"] as? String == "sessionCompleted")
        }
    }

    @Test func sessionEndDeletesOnlyThatSessionsRecord() throws {
        let sandbox = try Sandbox()
        try runCopilotBridge(event: "sessionStart", fixture: "copilot-sessionStart.json", in: sandbox)
        let other = sandbox.copilotSessions.appendingPathComponent("0a1b2c3d-0000-4000-8000-000000000001.hook.json")
        try sandbox.write("{}", to: other)
        let temp = sandbox.copilotSessions.appendingPathComponent(".\(copilotSessionID).hook.json.4242.tmp")
        try sandbox.write("{", to: temp)

        let result = try runCopilotBridge(event: "sessionEnd", fixture: "copilot-sessionEnd.json", in: sandbox)
        #expect(result.status == 0)
        #expect(result.stdout == "" && result.stderr == "")
        #expect(!sandbox.copilotRecordExists())
        #expect(!sandbox.exists(temp))
        #expect(sandbox.exists(other))
    }

    @Test func sessionStartPrunesOldRecordsAndStaleTempFiles() throws {
        let sandbox = try Sandbox()
        try runCopilotBridge(event: "agentStop", fixture: "copilot-agentStop.json", in: sandbox)
        let old = sandbox.copilotSessions.appendingPathComponent("old.hook.json")
        let recent = sandbox.copilotSessions.appendingPathComponent("recent.hook.json")
        let staleTemp = sandbox.copilotSessions.appendingPathComponent(".old.hook.json.1.tmp")
        for url in [old, recent, staleTemp] { try sandbox.write("{}", to: url) }
        let files = FileManager.default
        try files.setAttributes([.modificationDate: Date().addingTimeInterval(-8 * 86_400)], ofItemAtPath: old.path)
        try files.setAttributes([.modificationDate: Date().addingTimeInterval(-2 * 3600)], ofItemAtPath: staleTemp.path)

        try runCopilotBridge(event: "sessionStart", fixture: "copilot-sessionStart.json", in: sandbox)
        #expect(!sandbox.exists(old))
        #expect(!sandbox.exists(staleTemp))
        #expect(sandbox.exists(recent))
        #expect(sandbox.copilotRecordExists())
    }

    // MARK: - Nothing written

    @Test(arguments: ["preToolUse", "subagentStop", "bogus", "SessionStart", "a/b"])
    func eventsHeadroomDoesntTrackWriteNothing(event: String) throws {
        let sandbox = try Sandbox()
        try sandbox.placeCopilotScript()
        let before = sandbox.snapshot()
        let result = try runCopilotBridge(event: event, stdin: try fixtureText("copilot-snake-notification.json"), in: sandbox)
        #expect(result.status == 0)
        #expect(result.stdout == "" && result.stderr == "")
        #expect(sandbox.snapshot() == before)
    }

    @Test(arguments: ["../../evil", "a/b", "..", ".", "a b", String(repeating: "a", count: 300)])
    func unsafeSessionIDWritesNothing(id: String) throws {
        let sandbox = try Sandbox()
        try sandbox.placeCopilotScript()
        let before = sandbox.snapshot()
        let payload = #"{"cwd":"/Users/me/code/app","prompt":"x","sessionId":\#(try jsonText(id)),"timestamp":1}"#
        let result = try runCopilotBridge(event: "userPromptSubmitted", stdin: payload, in: sandbox)
        #expect(result.status == 0)
        #expect(sandbox.snapshot() == before)
    }

    @Test(arguments: ["", "   \n", "not json", "[1,2]", #"{"cwd":"/x","timestamp":1}"#])
    func malformedOrEmptyStdinWritesNothing(payload: String) throws {
        let sandbox = try Sandbox()
        try sandbox.placeCopilotScript()
        let before = sandbox.snapshot()
        let result = try runCopilotBridge(event: "userPromptSubmitted", stdin: payload, in: sandbox)
        #expect(result.status == 0)
        #expect(result.stdout == "" && result.stderr == "")
        #expect(sandbox.snapshot() == before)
    }

    @Test func noStdinExitsQuietly() throws {
        let sandbox = try Sandbox()
        let result = try runCopilotBridge(event: "sessionStart", stdin: nil, in: sandbox)
        #expect(result.status == 0)
        #expect(result.stdout == "" && result.stderr == "")
        #expect(!sandbox.copilotRecordExists())
    }

    @Test func unknownModeDoesNothing() throws {
        let sandbox = try Sandbox()
        try sandbox.placeCopilotScript()
        let before = sandbox.snapshot()
        let result = try runCopilotBridge(
            event: nil, stdin: try fixtureText("copilot-sessionStart.json"), in: sandbox, arguments: ["statusline"]
        )
        #expect(result.status == 0)
        #expect(sandbox.snapshot() == before)
    }

    @Test func runByARelativePathDoesNothing() throws {
        let sandbox = try Sandbox()
        try sandbox.placeCopilotScript()
        let before = sandbox.snapshot()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["headroom/bridge.sh", "hook", "sessionStart"]
        process.currentDirectoryURL = sandbox.copilot
        let result = try run(process, stdin: try fixtureText("copilot-sessionStart.json"), in: sandbox)
        #expect(result.status == 0)
        #expect(sandbox.snapshot() == before)
    }

    @Test func createsItsPrivateSessionsFolder() throws {
        let sandbox = try Sandbox()
        try runCopilotBridge(event: "sessionStart", fixture: "copilot-sessionStart.json", in: sandbox)
        let mode = try FileManager.default.attributesOfItem(atPath: sandbox.copilotSessions.path)[.posixPermissions] as? Int
        #expect(mode == 0o700)
    }

    // MARK: - Headroom uninstalled (1.0 §2.4)

    /// A sandbox whose `app-path` records a debug build that doesn't exist.
    private func sandboxRecordingAMissingApp() throws -> Sandbox {
        let sandbox = try Sandbox()
        try sandbox.placeCopilotScript()
        let app = sandbox.scratch.appendingPathComponent("DerivedData/Build/Products/Debug/Headroom.app", isDirectory: true)
        try sandbox.write(app.path, to: sandbox.copilotAppPath)
        return sandbox
    }

    @Test func doesNothingOnceHeadroomIsUninstalled() throws {
        let sandbox = try sandboxRecordingAMissingApp()
        try sandbox.write(#"{"v":1}"#, to: sandbox.copilotSessions.appendingPathComponent("\(copilotSessionID).hook.json"))
        let before = sandbox.snapshot()
        for (event, fixture) in copilotEventFixtures + [("sessionEnd", "copilot-sessionEnd.json")] {
            let result = try runCopilotBridge(event: event, fixture: fixture, in: sandbox)
            #expect(result.status == 0)
            #expect(result.stdout == "" && result.stderr == "")
        }
        // Nothing written, and nothing deleted.
        #expect(sandbox.snapshot() == before)
    }

    @Test func keepsWorkingWhileTheAppStoreContainerExists() throws {
        let sandbox = try sandboxRecordingAMissingApp()
        try sandbox.makeDirectory(sandbox.container)
        try runCopilotBridge(event: "sessionStart", fixture: "copilot-sessionStart.json", in: sandbox)
        #expect(sandbox.copilotRecordExists())
    }

    @Test func keepsWorkingWhileACopyIsInApplications() throws {
        let sandbox = try sandboxRecordingAMissingApp()
        try sandbox.makeDirectory(sandbox.applicationsCopy)
        try runCopilotBridge(event: "sessionStart", fixture: "copilot-sessionStart.json", in: sandbox)
        #expect(sandbox.copilotRecordExists())
    }

    @Test func keepsWorkingWhileTheRecordedAppExists() throws {
        let sandbox = try Sandbox()
        try sandbox.placeCopilotScript()
        let app = sandbox.scratch.appendingPathComponent("Headroom.app", isDirectory: true)
        try sandbox.makeDirectory(app)
        try sandbox.write(app.path + "\n", to: sandbox.copilotAppPath)
        try runCopilotBridge(event: "sessionStart", fixture: "copilot-sessionStart.json", in: sandbox)
        #expect(sandbox.copilotRecordExists())
    }

    // MARK: - The hook commands

    @Test func hookCommandRunsTheBridgeAndIsANoOpWithoutIt() throws {
        let sandbox = try Sandbox()
        let command = CopilotBridgeHooks.command(
            for: "sessionStart", scriptReference: CopilotBridgeHooks.scriptReference(paths: sandbox.copilotPaths, home: sandbox.home)
        )
        let payload = try fixtureText("copilot-sessionStart.json")

        let missing = try runShellCommand(command, stdin: payload, in: sandbox)
        #expect(missing.run.status == 0)
        #expect(missing.run.stdout == "" && missing.stderr == "")
        #expect(!sandbox.exists(sandbox.copilot))

        try sandbox.placeCopilotScript()
        let present = try runShellCommand(command, stdin: payload, in: sandbox)
        #expect(present.run.status == 0)
        #expect(present.run.stdout == "" && present.stderr == "")
        #expect(try sandbox.copilotRecord()["event"] as? String == "sessionStart")
    }

    @Test func customFolderCommandQuotesItsPath() throws {
        let sandbox = try Sandbox()
        let custom = CopilotPaths(copilotDirectory: sandbox.scratch.appendingPathComponent("it's copilot", isDirectory: true))
        let reference = CopilotBridgeHooks.scriptReference(paths: custom, home: sandbox.home)
        #expect(!reference.contains("$HOME"))
        try sandbox.write(CopilotBridgeScript.contents, to: custom.bridgeScriptFile)
        let result = try runShellCommand(
            CopilotBridgeHooks.command(for: "sessionStart", scriptReference: reference),
            stdin: try fixtureText("copilot-sessionStart.json"), in: sandbox
        )
        #expect(result.run.status == 0 && result.stderr == "")
        #expect(FileManager.default.fileExists(
            atPath: custom.bridgeSessionsDirectory.appendingPathComponent("\(copilotSessionID).hook.json").path
        ))
    }

    // MARK: - Ancestry

    @Test func stopsTheAncestryAtCopilot() throws {
        // copilot (a bash named so) -> bridge: the walk ends at the first process named copilot.
        let sandbox = try Sandbox()
        try sandbox.placeCopilotScript()
        let fakeCopilot = sandbox.scratch.appendingPathComponent("copilot")
        try FileManager.default.createSymbolicLink(at: fakeCopilot, withDestinationURL: URL(fileURLWithPath: "/bin/bash"))
        let payload = sandbox.scratch.appendingPathComponent("payload.json")
        try Data(try fixtureText("copilot-sessionStart.json").utf8).write(to: payload)

        let process = Process()
        process.executableURL = fakeCopilot
        // The trailing echo keeps bash from exec'ing the bridge in its own place, and prints the fake copilot's pid.
        process.arguments = ["-c", #"/bin/bash "$0" hook sessionStart < "$1"; echo $$"#, sandbox.copilotScript.path, payload.path]
        let result = try run(process, stdin: nil, in: sandbox)
        #expect(result.status == 0)
        let copilotPid = Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))

        let pids = try #require(try sandbox.copilotRecord()["pids"] as? [[Any]])
        #expect(pids.count == 1)
        #expect(pids.first?.first as? Int == copilotPid)
        #expect(pids.first?.last as? String == "copilot")
    }

    @Test func walksAtMostSixLevels() throws {
        let sandbox = try Sandbox()
        try sandbox.placeCopilotScript()
        let nest = sandbox.scratch.appendingPathComponent("nest.sh")
        try sandbox.write(
            """
            if [ "$1" -gt 0 ]; then
                /bin/bash "$0" $(($1 - 1))
            else
                /bin/bash "$SCRIPT" hook sessionStart < "$PAYLOAD"
            fi
            exit 0
            """,
            to: nest
        )
        let payload = sandbox.scratch.appendingPathComponent("payload.json")
        try Data(try fixtureText("copilot-sessionStart.json").utf8).write(to: payload)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [nest.path, "8"]
        _ = try run(process, stdin: nil, in: sandbox, environment: [
            "SCRIPT": sandbox.copilotScript.path, "PAYLOAD": payload.path,
        ])
        let pids = try #require(try sandbox.copilotRecord()["pids"] as? [[Any]])
        #expect(pids.count == 6)
        #expect(pids.allSatisfy { $0.count == 2 && $0[0] is Int && $0[1] as? String == "bash" })
    }

    // MARK: - Speed

    @Test func printsNothingAndIsFast() throws {
        let sandbox = try Sandbox()
        let cycle = copilotEventFixtures + [
            ("notification", "copilot-notification-elicitation.json"), ("sessionEnd", "copilot-sessionEnd.json"),
        ]
        // Spec: < 100 ms per run, judged on the median with room for tests running in parallel (TimingBound).
        var seconds: [String: [Double]] = [:]
        for _ in 0..<5 {
            for (event, fixture) in cycle {
                let result = try runCopilotBridge(event: event, fixture: fixture, in: sandbox)
                #expect(result.status == 0)
                #expect(result.stdout == "" && result.stderr == "")
                seconds[event, default: []].append(result.seconds)
            }
        }
        let bound = TimingBound(median: 0.3, ceiling: 2)
        for event in Set(cycle.map(\.0)) {
            bound.check(seconds[event] ?? [], event)
        }
    }

    @Test func headerVersionIsReadable() {
        #expect(CopilotBridgeScript.headerVersion(in: CopilotBridgeScript.contents) == CopilotBridgeScript.version)
        #expect(CopilotBridgeScript.contents.contains("# headroom-copilot-bridge v2\n"))
        #expect(CopilotBridgeScript.headerVersion(in: BridgeScript.contents) == nil)
        #expect(CopilotBridgeScript.headerVersion(in: "#!/bin/bash\n# headroom-copilot-bridge vX\n") == nil)
    }
}
#endif
