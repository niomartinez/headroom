import Foundation
import Testing
@testable import SetupKit

@Suite("bridge.sh hook mode")
struct BridgeScriptHookTests {
    let sessionID = "0f5c2a7e-1b3d-4c5e-8f90-a1b2c3d4e5f6"
    let recordKeys: Set<String> = ["v", "ts", "pid", "event", "session_id", "cwd", "transcript_path", "notification_type"]

    @Test(arguments: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop"])
    func eachEventWritesAValidRecord(event: String) throws {
        let sandbox = try Sandbox()
        let extra: String = switch event {
        case "UserPromptSubmit": #","prompt":"hello""#
        case "PreToolUse": #","tool_name":"Bash","tool_input":{"command":"ls","cwd":"/elsewhere"}"#
        case "PostToolUse":
            #","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{"stdout":"a\nb","cwd":"/elsewhere"}"#
        case "Notification": #","message":"Claude needs your permission to use Bash","notification_type":"permission_prompt""#
        case "SessionStart": #","source":"startup""#
        default: #","stop_hook_active":false"#
        }
        let before = Date().timeIntervalSince1970

        let result = try runBridge("hook", stdin: try hookPayload(event: event, extra: extra), in: sandbox)

        #expect(result.status == 0)
        #expect(result.stdout == "")
        let record = try hookRecord(sessionID, in: sandbox)
        #expect(Set(record.keys) == recordKeys)
        #expect(record["v"] as? Int == 1)
        let ts = try #require(record["ts"] as? Double)
        #expect(ts >= before.rounded(.down) && ts <= Date().timeIntervalSince1970 + 1)
        #expect((record["pid"] as? Int ?? 0) > 1)
        #expect(record["event"] as? String == event)
        #expect(record["session_id"] as? String == sessionID)
        #expect(record["cwd"] as? String == "/Users/me/app")
        #expect(record["transcript_path"] as? String == "/Users/me/.claude/projects/-Users-me-app/\(sessionID).jsonl")
        #expect(record["notification_type"] as? String == (event == "Notification" ? "permission_prompt" : ""))
    }

    /// Older Claude Code versions send no `notification_type`; the idle prompt is then recognized
    /// by its message (spec §2.5), which itself is never stored.
    @Test(arguments: [
        (#","message":"Claude is waiting for your input""#, "idle_prompt"),
        (#","message":"Claude needs your permission to use Bash""#, ""),
        (#","message":"Claude is waiting for your input","notification_type":"permission_prompt""#, "permission_prompt"),
        ("", ""),
    ])
    func notificationTypeFallsBackToTheIdleMessage(extra: String, expected: String) throws {
        let sandbox = try Sandbox()
        try runBridge("hook", stdin: try hookPayload(event: "Notification", extra: extra), in: sandbox)
        let record = try hookRecord(sessionID, in: sandbox)
        #expect(record["notification_type"] as? String == expected)
        #expect(!sandbox.anyFileContains("Claude is waiting"))
    }

    @Test func promptTextNeverReachesAnyFile() throws {
        let sandbox = try Sandbox()
        let prompt = "SECRET plan: \"quoted\" \\ back\\\\slash\nnew line \"session_id\":\"../../evil\" "
            + "\"cwd\":\"/evil\" \"hook_event_name\":\"SessionEnd\" }{ \u{1F512}"
        // The prompt comes first so a naive extractor would pick up the fake keys inside it.
        let payload = "{\"prompt\":\(try jsonText(prompt)),\"session_id\":\"\(sessionID)\","
            + "\"transcript_path\":\"/Users/me/t.jsonl\",\"cwd\":\"/Users/me/app\",\"hook_event_name\":\"UserPromptSubmit\"}"

        let result = try runBridge("hook", stdin: payload, in: sandbox)

        #expect(result.status == 0)
        #expect(result.stdout == "")
        let record = try hookRecord(sessionID, in: sandbox)
        #expect(Set(record.keys) == recordKeys)
        #expect(record["event"] as? String == "UserPromptSubmit")
        #expect(record["cwd"] as? String == "/Users/me/app")
        #expect(!sandbox.anyFileContains("SECRET"))
        #expect(!sandbox.anyFileContains("quoted"))
        #expect(!sandbox.exists(sandbox.claude.appendingPathComponent("evil.hook.json")))
    }

    @Test func escapedAndUnicodeValuesRoundTrip() throws {
        let sandbox = try Sandbox()
        let cwd = "/Users/me/caf\u{e9} \u{2615}/a \"quoted\" \\ dir"
        let payload = try hookPayload(event: "Stop", cwd: cwd)
            .replacingOccurrences(of: "/Users/me/.claude", with: "\\/Users\\/me\\/.claude\\u00e9")

        for locale in ["C", "en_US.UTF-8"] {
            try? FileManager.default.removeItem(at: sandbox.sessions)
            try runBridge("hook", stdin: payload, in: sandbox, environment: ["LC_ALL": locale, "LANG": locale])
            let record = try hookRecord(sessionID, in: sandbox)
            #expect(record["cwd"] as? String == cwd)
            #expect((record["transcript_path"] as? String)?.hasPrefix("/Users/me/.claude\u{e9}/projects/") == true)
        }
    }

    @Test func sessionEndDeletesOnlyThatSessionsFiles() throws {
        let sandbox = try Sandbox()
        let other = "11111111-2222-3333-4444-555555555555"
        try runBridge("hook", stdin: try hookPayload(event: "Stop"), in: sandbox)
        try runBridge("statusline", stdin: try fixtureText("statusline-payload.json"), in: sandbox)
        try runBridge("hook", stdin: try hookPayload(event: "Stop", sessionID: other), in: sandbox)
        #expect(sandbox.exists(sandbox.sessions.appendingPathComponent("\(sessionID).statusline.json")))

        let result = try runBridge("hook", stdin: try hookPayload(event: "SessionEnd", extra: #","reason":"exit""#), in: sandbox)

        #expect(result.status == 0)
        #expect(result.stdout == "")
        let remaining = try FileManager.default.contentsOfDirectory(atPath: sandbox.sessions.path)
        #expect(remaining == ["\(other).hook.json"])
    }

    @Test func sessionStartPrunesFilesOlderThanSevenDays() throws {
        let sandbox = try Sandbox()
        let old = sandbox.sessions.appendingPathComponent("old-session.hook.json")
        let recent = sandbox.sessions.appendingPathComponent("recent-session.hook.json")
        try sandbox.write("{}", to: old)
        try sandbox.write("{}", to: recent)
        let eightDaysAgo = Date().addingTimeInterval(-8 * 24 * 3600)
        let sixDaysAgo = Date().addingTimeInterval(-6 * 24 * 3600)
        try FileManager.default.setAttributes([.modificationDate: eightDaysAgo], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: sixDaysAgo], ofItemAtPath: recent.path)

        try runBridge("hook", stdin: try hookPayload(event: "Stop"), in: sandbox)
        #expect(sandbox.exists(old))

        try runBridge("hook", stdin: try hookPayload(event: "SessionStart"), in: sandbox)
        #expect(!sandbox.exists(old))
        #expect(sandbox.exists(recent))
        #expect(sandbox.exists(sandbox.sessions.appendingPathComponent("\(sessionID).hook.json")))
    }

    // MARK: - Temp files

    /// Claude Code kills a status line run when a newer one starts, which can leave a temp file.
    @Test func sessionEndDeletesThatSessionsTempFiles() throws {
        let sandbox = try Sandbox()
        let other = "11111111-2222-3333-4444-555555555555"
        try runBridge("hook", stdin: try hookPayload(event: "Stop"), in: sandbox)
        let mine = [".\(sessionID).statusline.json.123.tmp", ".\(sessionID).hook.json.456.tmp"]
        let theirs = [".\(other).statusline.json.789.tmp", ".\(sessionID)x.hook.json.1.tmp"]
        for name in mine + theirs {
            try sandbox.write("", to: sandbox.sessions.appendingPathComponent(name))
        }

        try runBridge("hook", stdin: try hookPayload(event: "SessionEnd"), in: sandbox)

        #expect(sandbox.entries(in: sandbox.sessions, prefix: ".") == theirs.sorted())
    }

    @Test func sessionStartPrunesStaleTempFiles() throws {
        let sandbox = try Sandbox()
        let other = "11111111-2222-3333-4444-555555555555"
        try runBridge("statusline", stdin: try fixtureText("statusline-payload.json"), in: sandbox)
        try sandbox.saveOriginalStatusLine(["type": "command", "command": "echo mine"])
        let stale = [
            sandbox.bridgeDirectory.appendingPathComponent(".statusline-latest.json.111.tmp"),
            sandbox.sessions.appendingPathComponent(".\(other).statusline.json.333.tmp"),
        ]
        let fresh = [
            sandbox.bridgeDirectory.appendingPathComponent(".statusline-latest.json.222.tmp"),
            sandbox.sessions.appendingPathComponent(".\(other).hook.json.444.tmp"),
        ]
        for url in stale + fresh {
            try sandbox.write("", to: url)
        }
        let twoHoursAgo = Date().addingTimeInterval(-2 * 3600)
        // Only temp files go: the bridge's own files are as old as the connection.
        let kept = [sandbox.statusLineLatest, sandbox.originalStatusLine, sandbox.originalStatusLineCommand, sandbox.script]
        for url in stale + kept {
            try FileManager.default.setAttributes([.modificationDate: twoHoursAgo], ofItemAtPath: url.path)
        }

        try runBridge("hook", stdin: try hookPayload(event: "SessionStart"), in: sandbox)

        for url in stale { #expect(!sandbox.exists(url), "\(url.lastPathComponent)") }
        for url in fresh + kept { #expect(sandbox.exists(url), "\(url.lastPathComponent)") }
    }

    /// A run killed (SIGTERM, as Claude Code aborts a status line when a newer one starts) after it
    /// created its temp file but before moving it into place removes the temp file. To hold the run
    /// at exactly that point, its temp file is a FIFO nobody reads: writing a large payload blocks.
    @Test func aKilledWriteLeavesNoTempFile() throws {
        let sandbox = try Sandbox()
        try sandbox.placeScript()
        // The wrapper keeps its pid when it execs the bridge, so it knows the temp file's name.
        let wrapper = sandbox.scratch.appendingPathComponent("wrapper.sh")
        try sandbox.write(
            """
            mkfifo "$HOME/.claude/headroom/.statusline-latest.json.$$.tmp" || exit 1
            while [ ! -e "$GO" ]; do sleep 0.01; done
            exec /bin/bash "$SCRIPT" statusline
            """,
            to: wrapper
        )
        let go = sandbox.scratch.appendingPathComponent("go")
        let base = try #require(try parseJSON(try fixtureText("statusline-payload.json")) as? [String: Any])
        let input = sandbox.scratch.appendingPathComponent("payload.json")
        try Data(try jsonText(base.merging(["padding": String(repeating: "x", count: 300_000)]) { $1 }).utf8).write(to: input)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [wrapper.path]
        process.environment = [
            "HOME": sandbox.home.path, "PATH": "/usr/bin:/bin", "GO": go.path, "SCRIPT": sandbox.script.path,
        ]
        process.standardInput = try FileHandle(forReadingFrom: input)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        var reader: Int32 = -1
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            if reader >= 0 { close(reader) }
        }
        let fifoPath = sandbox.bridgeDirectory.appendingPathComponent(".statusline-latest.json.\(process.processIdentifier).tmp").path
        let deadline = Date().addingTimeInterval(5)
        while reader < 0, Date() < deadline {
            usleep(10_000)
            reader = open(fifoPath, O_RDONLY | O_NONBLOCK)
        }
        try #require(reader >= 0, "the wrapper never created the FIFO")
        try sandbox.write("", to: go)
        usleep(500_000)  // the bridge fills the FIFO's buffer and blocks in its write

        process.terminate()
        usleep(100_000)
        // Let the write finish so the bridge can act on the signal.
        var buffer = [UInt8](repeating: 0, count: 65_536)
        let exitDeadline = Date().addingTimeInterval(5)
        while process.isRunning, Date() < exitDeadline {
            if read(reader, &buffer, buffer.count) <= 0 { usleep(5_000) }
        }

        #expect(!process.isRunning)
        #expect(sandbox.bridgeTempFiles().isEmpty, "\(sandbox.bridgeTempFiles())")
        #expect(!sandbox.exists(sandbox.statusLineLatest))
    }

    @Test(arguments: [
        "", " ", "\n\n", "not json", "{", "}", "[]", "null", "{}",
        #"{"session_id":"abc","hook_event_name":"Stop""#,
        #"{"session_id":"abc"}"#,
        #"{"hook_event_name":"Stop"}"#,
        #"{"session_id":"abc","hook_event_name":"Sto p"}"#,
        #"{"session_id":"abc","hook_event_name":""}"#,
        #"{"session_id":12,"hook_event_name":"Stop"}"#,
        "\u{0}\u{1}\u{7f}garbage\u{ff}",
    ])
    func malformedOrEmptyStdinWritesNothing(payload: String) throws {
        let sandbox = try Sandbox()
        try sandbox.placeScript()
        let before = sandbox.snapshot()

        let result = try runBridge("hook", stdin: payload, in: sandbox)

        #expect(result.status == 0)
        #expect(result.stdout == "")
        #expect(sandbox.snapshot() == before)
    }

    /// Hooks of parallel tool calls run at the same time. macOS then fails `stat("/dev/fd/0")`
    /// with EBADF although fd 0 is open, so the bridge must not judge stdin through /dev/fd:
    /// it would replace the payload with /dev/null and silently drop the event.
    @Test func keepsThePayloadWhileOtherProcessesLookUpDevFd() throws {
        let sandbox = try Sandbox()
        let payload = try fixtureText("statusline-payload.json")
        let prober = DevFdProber(threads: 2)
        defer { prober.stop() }

        var lostEvents: [Int] = []
        var wrongStatusLines: [String] = []
        for i in 0..<30 {
            let id = "parallel-\(i)"
            try runBridge("hook", stdin: try hookPayload(event: "PreToolUse", sessionID: id), in: sandbox)
            if !sandbox.exists(sandbox.sessions.appendingPathComponent("\(id).hook.json")) { lostEvents.append(i) }
            let line = try runBridge("statusline", stdin: payload, in: sandbox).stdout
            if line != "5h 20% · wk 90% · ctx 26%\n" { wrongStatusLines.append(line) }
        }

        #expect(lostEvents.isEmpty, "hook payloads dropped in runs \(lostEvents)")
        #expect(wrongStatusLines.isEmpty, "status lines printed: \(wrongStatusLines)")
    }

    /// A closed stdin (not /dev/null) must neither block nor be mistaken for a payload.
    @Test(arguments: ["hook", "statusline"])
    func closedStdinAndStderrExitQuietly(mode: String) throws {
        let sandbox = try Sandbox()
        try sandbox.placeScript()
        let before = sandbox.snapshot()

        let result = try runBridgeWithClosedStdio(mode, in: sandbox)

        #expect(result.status == 0)
        #expect(result.stdout == "")
        #expect(result.seconds < 5)
        #expect(sandbox.snapshot() == before)
    }

    @Test func noStdinExitsQuietly() throws {
        let sandbox = try Sandbox()
        try sandbox.placeScript()
        let before = sandbox.snapshot()
        let result = try runBridge("hook", stdin: nil, in: sandbox)
        #expect(result.status == 0)
        #expect(result.stdout == "")
        #expect(sandbox.snapshot() == before)
    }

    @Test(arguments: ["../../evil", "a/b", "..", ".", "../..", "a b", #"a\/b"#, #".."#, String(repeating: "a", count: 300)])
    func unsafeSessionIDWritesNothingAnywhere(id: String) throws {
        let sandbox = try Sandbox()
        try sandbox.placeScript()
        // Bait: files a SessionEnd traversal would delete ("../../evil" and "../..").
        try sandbox.write("{}", to: sandbox.claude.appendingPathComponent("evil.hook.json"))
        try sandbox.write("{}", to: sandbox.bridgeDirectory.appendingPathComponent("...hook.json"))
        let before = sandbox.snapshot()

        for event in ["SessionStart", "UserPromptSubmit", "Stop", "SessionEnd"] {
            let payload = #"{"session_id":"\#(id)","cwd":"/x","hook_event_name":"\#(event)"}"#
            let result = try runBridge("hook", stdin: payload, in: sandbox)
            #expect(result.status == 0)
            #expect(result.stdout == "")
        }

        #expect(sandbox.snapshot() == before)
    }

    @Test func unknownModeDoesNothing() throws {
        let sandbox = try Sandbox()
        try sandbox.placeScript()
        let before = sandbox.snapshot()
        let result = try runBridge("bogus", stdin: try hookPayload(event: "Stop"), in: sandbox)
        #expect(result.status == 0)
        #expect(result.stdout == "")
        #expect(sandbox.snapshot() == before)
    }

    @Test func printsNothingAndIsFast() throws {
        let sandbox = try Sandbox()
        let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "Notification", "SessionEnd"]
        let statusLinePayload = try fixtureText("statusline-payload.json")
        // Spec: < 100 ms per invocation. Each kind of run is timed over whole session cycles, and
        // judged on its median (TimingBound): the bound is looser because tests run in parallel.
        var seconds: [String: [Double]] = [:]
        for _ in 0..<5 {
            for event in events {
                let result = try runBridge("hook", stdin: try hookPayload(event: event), in: sandbox)
                #expect(result.status == 0)
                #expect(result.stdout == "")
                seconds[event, default: []].append(result.seconds)
            }
            let statusLine = try runBridge("statusline", stdin: statusLinePayload, in: sandbox)
            #expect(statusLine.status == 0)
            seconds["statusline", default: []].append(statusLine.seconds)
        }
        let bound = TimingBound(median: 0.3, ceiling: 2)
        for kind in events + ["statusline"] {
            bound.check(seconds[kind] ?? [], kind)
        }
    }

    @Test func timingBoundsJudgeTheMedian() {
        #expect(medianOf([0.9, 0.1, 0.2]) == 0.2)
        #expect(medianOf([0.4, 0.1, 0.2, 0.3]) == 0.25)
        #expect(medianOf([]) == 0)
    }

    @Test func largePayloadStaysQuick() throws {
        let sandbox = try Sandbox()
        let content = String(repeating: "x\\\"y\\\\ ", count: 150_000)
        let payload = try hookPayload(event: "PreToolUse", extra: #","tool_name":"Write","tool_input":{"content":"\#(content)"}"#)

        var seconds: [Double] = []
        for _ in 0..<3 {
            let result = try runBridge("hook", stdin: payload, in: sandbox)
            #expect(result.status == 0)
            seconds.append(result.seconds)
        }

        #expect(try hookRecord(sessionID, in: sandbox)["event"] as? String == "PreToolUse")
        // About 0.1 s; a regex that backtracks over the 1 MB payload takes far longer.
        TimingBound(median: 1.5, ceiling: 10).check(seconds, "1 MB PreToolUse payload")
    }

    // MARK: - Claude pid

    /// Runs the hook below a fake `claude` process with `depth` bash levels in between.
    /// Returns the recorded pid and the pids written by each level (0 = the hook's parent).
    private func runBelowFakeClaude(depth: Int) throws -> (recorded: Int?, levels: [Int: Int]) {
        let sandbox = try Sandbox()
        try sandbox.placeScript()
        let fakeClaude = sandbox.scratch.appendingPathComponent("claude")
        try FileManager.default.createSymbolicLink(at: fakeClaude, withDestinationURL: URL(fileURLWithPath: "/bin/bash"))
        let nest = sandbox.scratch.appendingPathComponent("nest.sh")
        try sandbox.write(
            """
            echo $$ > "$PIDS/$1"
            if [ "$1" -gt 0 ]; then
                /bin/bash "$0" $(($1 - 1))
            else
                /bin/bash "$SCRIPT" hook < "$PAYLOAD"
            fi
            exit 0
            """,
            to: nest
        )
        let pids = sandbox.scratch.appendingPathComponent("pids", isDirectory: true)
        try FileManager.default.createDirectory(at: pids, withIntermediateDirectories: true)
        let payload = sandbox.scratch.appendingPathComponent("payload.json")
        try Data(try hookPayload(event: "Stop").utf8).write(to: payload)

        let process = Process()
        process.executableURL = fakeClaude
        process.arguments = [nest.path, String(depth)]
        let result = try run(process, stdin: nil, in: sandbox, environment: [
            "PIDS": pids.path, "SCRIPT": sandbox.script.path, "PAYLOAD": payload.path,
        ])
        #expect(result.status == 0)

        var levels: [Int: Int] = [:]
        for level in 0...depth {
            let text = try String(contentsOf: pids.appendingPathComponent(String(level)), encoding: .utf8)
            levels[level] = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (try hookRecord(sessionID, in: sandbox)["pid"] as? Int, levels)
    }

    @Test func recordsTheNearestClaudeAncestor() throws {
        // bridge -> level 0 -> level 1 -> level 2 -> level 3 (named claude)
        let (recorded, levels) = try runBelowFakeClaude(depth: 3)
        #expect(recorded != nil)
        #expect(recorded == levels[3])
    }

    @Test func fallsBackToTheParentBeyondSixLevels() throws {
        let (recorded, levels) = try runBelowFakeClaude(depth: 8)
        #expect(recorded != nil)
        #expect(recorded == levels[0])
    }
}
