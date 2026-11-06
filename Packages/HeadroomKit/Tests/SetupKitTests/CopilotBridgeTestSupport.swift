#if HEADROOM_COPILOT_CLI
import Foundation
import HeadroomModel
import Testing
@testable import SetupKit

/// The session id every Copilot fixture payload uses.
let copilotSessionID = "5d3f8a2c-7b1e-4c9d-a6f0-2e8b4c1d9a7f"

/// Text the fixtures put in every field that can hold what the user typed or what a tool did (prompt,
/// initialPrompt, message, toolArgs, toolResult, error): it must never reach a file.
let copilotPromptMarker = "PROMPT-TEXT"

/// The fixture payload for each hook event Headroom registers, as Copilot CLI 1.0.88 sends them (camelCase).
let copilotEventFixtures: [(event: String, fixture: String)] = [
    ("sessionStart", "copilot-sessionStart.json"),
    ("userPromptSubmitted", "copilot-userPromptSubmitted.json"),
    ("postToolUse", "copilot-postToolUse.json"),
    ("notification", "copilot-notification-permission.json"),
    ("agentStop", "copilot-agentStop.json"),
    ("errorOccurred", "copilot-errorOccurred.json"),
]

extension Sandbox {
    /// `~/.copilot` in the sandbox home.
    var copilot: URL { home.appendingPathComponent(".copilot", isDirectory: true) }
    var copilotPaths: CopilotPaths { CopilotPaths(copilotDirectory: copilot) }
    var copilotScript: URL { copilotPaths.bridgeScriptFile }
    var copilotSessions: URL { copilotPaths.bridgeSessionsDirectory }
    var copilotAppPath: URL { copilotPaths.bridgeDirectory.appendingPathComponent("app-path") }

    /// An installer for the sandbox's `~/.copilot` that records `appBundlePath`.
    func copilotInstaller(appBundlePath: String? = nil) -> CopilotBridgeInstaller {
        CopilotBridgeInstaller(paths: copilotPaths, home: home, appBundlePath: appBundlePath)
    }

    /// Writes the Copilot bridge script where the installer would put it, with its /Applications/Headroom.app check
    /// pointed at `applicationsCopy`: whether the real one exists depends on the machine running the tests.
    func placeCopilotScript() throws {
        let contents = CopilotBridgeScript.contents
        try #require(contents.contains("\"\(BridgeScript.applicationsCopyPath)\""))
        try write(
            contents.replacingOccurrences(of: BridgeScript.applicationsCopyPath, with: applicationsCopy.path),
            to: copilotScript
        )
    }

    /// The record the Copilot bridge wrote for `sessionID`.
    func copilotRecord(_ sessionID: String = copilotSessionID) throws -> [String: Any] {
        let url = copilotSessions.appendingPathComponent("\(sessionID).hook.json")
        return try #require(try jsonObject(at: url) as? [String: Any])
    }

    func copilotRecordExists(_ sessionID: String = copilotSessionID) -> Bool {
        exists(copilotSessions.appendingPathComponent("\(sessionID).hook.json"))
    }
}

struct CopilotBridgeRun {
    var status: Int32
    var stdout: String
    var stderr: String
    var seconds: Double
}

/// Runs `/bin/bash <script> hook [event]` with `HOME` pointed at the sandbox, `stdin` as input, and stdout and
/// stderr captured. Places the script first when it isn't there.
@discardableResult
func runCopilotBridge(
    event: String?,
    stdin: String?,
    in sandbox: Sandbox,
    arguments: [String]? = nil
) throws -> CopilotBridgeRun {
    if !sandbox.exists(sandbox.copilotScript) { try sandbox.placeCopilotScript() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [sandbox.copilotScript.path] + (arguments ?? (["hook"] + (event.map { [$0] } ?? [])))
    let errors = sandbox.scratch.appendingPathComponent("stderr-\(UUID().uuidString)")
    FileManager.default.createFile(atPath: errors.path, contents: nil)
    let handle = try FileHandle(forWritingTo: errors)
    defer { try? handle.close() }
    let result = try run(process, stdin: stdin, in: sandbox, standardError: handle)
    return CopilotBridgeRun(
        status: result.status,
        stdout: result.stdout,
        stderr: try String(contentsOf: errors, encoding: .utf8),
        seconds: result.seconds
    )
}

/// Runs the bridge for `event` with a fixture payload.
@discardableResult
func runCopilotBridge(event: String, fixture name: String, in sandbox: Sandbox) throws -> CopilotBridgeRun {
    try runCopilotBridge(event: event, stdin: try fixtureText(name), in: sandbox)
}
#endif
