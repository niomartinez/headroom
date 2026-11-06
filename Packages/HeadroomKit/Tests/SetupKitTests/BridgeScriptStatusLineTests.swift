import Foundation
import Testing
@testable import SetupKit

@Suite("bridge.sh statusline mode")
struct BridgeScriptStatusLineTests {
    let sessionID = "0f5c2a7e-1b3d-4c5e-8f90-a1b2c3d4e5f6"

    @Test func headerNamesTheVersion() {
        let lines = BridgeScript.contents.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.first == "#!/bin/bash")
        #expect(lines.dropFirst().first == "# headroom-bridge v\(BridgeScript.version)")
        #expect(BridgeScript.headerVersion(in: BridgeScript.contents) == BridgeScript.version)
        #expect(BridgeScript.headerVersion(in: "#!/bin/bash\n# headroom-bridge v0\n") == 0)
        #expect(BridgeScript.headerVersion(in: "#!/bin/bash\necho hi\n") == nil)
        #expect(BridgeScript.headerVersion(in: "") == nil)
    }

    @Test func writesLatestAndSessionFilesAsValidJSON() throws {
        let sandbox = try Sandbox()
        let payload = try fixtureText("statusline-payload.json")
        let before = Date().timeIntervalSince1970

        let result = try runBridge("statusline", stdin: payload, in: sandbox)

        #expect(result.status == 0)
        let latest = try jsonObject(at: sandbox.statusLineLatest)
        #expect(jsonEqual(latest, try parseJSON(payload)))
        let record = try #require(
            try jsonObject(at: sandbox.sessions.appendingPathComponent("\(sessionID).statusline.json")) as? [String: Any]
        )
        #expect(Set(record.keys) == ["v", "ts", "pid", "payload"])
        #expect(record["v"] as? Int == 1)
        let ts = try #require(record["ts"] as? Double)
        #expect(ts >= before.rounded(.down) && ts <= Date().timeIntervalSince1970 + 1)
        #expect((record["pid"] as? Int ?? 0) > 1)
        #expect(jsonEqual(record["payload"], try parseJSON(payload)))
    }

    @Test func skipsLatestFileWithoutRateLimits() throws {
        let sandbox = try Sandbox()
        let payload = "{\"session_id\":\"\(sessionID)\",\"cwd\":\"/Users/me/app\",\"context_window\":{\"used_percentage\":3}}"

        let result = try runBridge("statusline", stdin: payload, in: sandbox)

        #expect(result.status == 0)
        #expect(!sandbox.exists(sandbox.statusLineLatest))
        let record = try jsonObject(at: sandbox.sessions.appendingPathComponent("\(sessionID).statusline.json"))
        #expect(jsonEqual((record as? [String: Any])?["payload"], try parseJSON(payload)))
        #expect(result.stdout == "ctx 3%\n")
    }

    @Test func printsTheSpecExampleSummary() throws {
        let sandbox = try Sandbox()
        let result = try runBridge("statusline", stdin: try fixtureText("statusline-payload.json"), in: sandbox)
        #expect(result.stdout.trimmingCharacters(in: .newlines) == "5h 20% · wk 90% · ctx 26%")
    }

    @Test(arguments: [
        // Rounds half up and omits a missing weekly limit.
        (#"{"session_id":"s1","context_window":{"used_percentage":26.5,"current_usage":{"input_tokens":1}},"rate_limits":{"five_hour":{"used_percentage":20.4,"resets_at":1}}}"#,
         "5h 20% · ctx 27%"),
        // A nested object's used_percentage never counts for its parent.
        (#"{"session_id":"s1","context_window":{"current_usage":{"used_percentage":50},"used_percentage":null}}"#,
         ""),
        (#"{"session_id":"s1","rate_limits":{"seven_day":{"used_percentage":99.5}}}"#, "wk 100%"),
        (#"{"session_id":"s1","context_window":{"used_percentage":5e-7}}"#, "ctx 0%"),
        (#"{"session_id":"s1","context_window":{"used_percentage":1e3}}"#, ""),
        // Pretty-printed payloads work too.
        ("{\n  \"session_id\" : \"s1\",\n  \"rate_limits\" : {\n    \"five_hour\" : {\n      \"used_percentage\" : 7\n    }\n  }\n}\n",
         "5h 7%"),
    ])
    func roundsAndOmitsParts(payload: String, expected: String) throws {
        let sandbox = try Sandbox()
        let result = try runBridge("statusline", stdin: payload, in: sandbox)
        #expect(result.status == 0)
        #expect(result.stdout.trimmingCharacters(in: .newlines) == expected)
    }

    @Test func chainsTheOriginalStatusLineAndPrintsOnlyItsOutput() throws {
        let sandbox = try Sandbox()
        let command = #"cat > "$HOME/chained-stdin.json"; printf '%s' 'mine: "quoted" \ back'; exit 3"#
        try sandbox.saveOriginalStatusLine(["type": "command", "command": command, "padding": 0])
        let payload = try fixtureText("statusline-payload.json")

        let result = try runBridge("statusline", stdin: payload, in: sandbox)

        #expect(result.stdout == #"mine: "quoted" \ back"#)
        #expect(result.status == 0)
        let chainedStdin = try String(contentsOf: sandbox.home.appendingPathComponent("chained-stdin.json"), encoding: .utf8)
        #expect(chainedStdin == payload)
        #expect(sandbox.exists(sandbox.statusLineLatest))
    }

    @Test func chainedCommandSeesTheUsersLocale() throws {
        let sandbox = try Sandbox()
        try sandbox.saveOriginalStatusLine(["type": "command", "command": #"printf '%s|%s' "$LC_ALL" "$LANG""#])

        let withLocale = try runBridge(
            "statusline", stdin: try fixtureText("statusline-payload.json"), in: sandbox,
            environment: ["LC_ALL": "en_US.UTF-8", "LANG": "en_US.UTF-8"]
        )
        let withoutLocale = try runBridge("statusline", stdin: try fixtureText("statusline-payload.json"), in: sandbox)

        #expect(withLocale.stdout == "en_US.UTF-8|en_US.UTF-8")
        #expect(withoutLocale.stdout == "|")
    }

    @Test(arguments: [BridgeInstaller.statusLineCommand, #"/bin/bash "$HOME/.claude/headroom/bridge.sh" statusline"#])
    func neverChainsItself(command: String) throws {
        let sandbox = try Sandbox()
        try sandbox.saveOriginalStatusLine(["type": "command", "command": command])

        let result = try runBridge("statusline", stdin: try fixtureText("statusline-payload.json"), in: sandbox)

        #expect(result.stdout.trimmingCharacters(in: .newlines) == "5h 20% · wk 90% · ctx 26%")
    }

    /// Only a regular file is run: a FIFO there would block every status line.
    @Test func ignoresASavedCommandThatIsNotARegularFile() throws {
        let sandbox = try Sandbox()
        try makeFIFO(at: sandbox.originalStatusLineCommand)

        let result = try runBridge("statusline", stdin: try fixtureText("statusline-payload.json"), in: sandbox)

        #expect(result.stdout == "5h 20% · wk 90% · ctx 26%\n")
        #expect(result.seconds < 5)
    }

    @Test(arguments: ["../../evil", "a/b", "..", ".", "", "a b", #"a\/b"#])
    func unsafeSessionIDWritesNothingButStillPrints(id: String) throws {
        let sandbox = try Sandbox()
        try sandbox.placeScript()
        let before = sandbox.snapshot()
        let payload = #"{"session_id":"\#(id)","rate_limits":{"five_hour":{"used_percentage":20}}}"#

        let result = try runBridge("statusline", stdin: payload, in: sandbox)

        #expect(result.status == 0)
        #expect(sandbox.snapshot() == before)
        #expect(result.stdout == "5h 20%\n", "stdout \(result.stdout.debugDescription) status \(result.status) secs \(result.seconds)")
    }

    @Test(arguments: ["", "   \n", "not json", "{", "[1,2]", #"{"session_id":"s1""#, "null"])
    func malformedPayloadWritesNothing(payload: String) throws {
        let sandbox = try Sandbox()
        try sandbox.placeScript()
        let before = sandbox.snapshot()

        let result = try runBridge("statusline", stdin: payload, in: sandbox)

        #expect(result.status == 0)
        #expect(result.stdout == "")
        #expect(sandbox.snapshot() == before)
    }

    @Test func noStdinDoesNotBlock() throws {
        let sandbox = try Sandbox()
        let result = try runBridge("statusline", stdin: nil, in: sandbox)
        #expect(result.status == 0)
        #expect(result.stdout == "")
        #expect(result.seconds < 5)
    }
}
