import Foundation
import HeadroomModel
import Testing
@testable import SetupKit

/// Deleting Headroom leaves the bridge wired into settings.json: nothing runs "Disconnect terminal".
/// The bridge then writes nothing, and the status line is the user's own again (or none). Headroom
/// counts as installed while the app "Connect terminal" ran from (`app-path`), /Applications/Headroom.app
/// or the App Store version's container exists; installs that recorded no app keep working.
@Suite("bridge.sh once Headroom is uninstalled")
struct BridgeUninstalledTests {
    let sessionID = "0f5c2a7e-1b3d-4c5e-8f90-a1b2c3d4e5f6"
    let ourStatusLine = "5h 20% · wk 90% · ctx 26%\n"

    /// A trace of the app that keeps the bridge working.
    enum Trace: String, CaseIterable, CustomTestStringConvertible {
        case recordedApp
        case applicationsCopy
        case container
        var testDescription: String { rawValue }
    }

    /// A sandbox with the script placed and `~/.claude/headroom/app-path` recording a debug build's
    /// bundle, which does not exist unless `traces` says so.
    func makeSandbox(with traces: Set<Trace> = []) throws -> (Sandbox, app: URL) {
        let sandbox = try Sandbox()
        try sandbox.placeScriptCheckingSandboxApplications()
        let app = sandbox.scratch.appendingPathComponent("DerivedData/Build/Products/Debug/Headroom.app", isDirectory: true)
        try sandbox.write(app.path, to: sandbox.appPath)
        if traces.contains(.recordedApp) { try sandbox.makeDirectory(app) }
        if traces.contains(.applicationsCopy) { try sandbox.makeDirectory(sandbox.applicationsCopy) }
        if traces.contains(.container) { try sandbox.makeDirectory(sandbox.container) }
        return (sandbox, app)
    }

    /// Runs a hook and a status line, and checks the bridge wrote both.
    func expectWorking(_ sandbox: Sandbox, _ comment: Comment? = nil) throws {
        let hook = try runBridge("hook", stdin: try hookPayload(event: "Stop"), in: sandbox)
        #expect(hook.status == 0)
        #expect(sandbox.exists(sandbox.sessions.appendingPathComponent("\(sessionID).hook.json")), comment)
        let statusLine = try runBridge("statusline", stdin: try fixtureText("statusline-payload.json"), in: sandbox)
        #expect(statusLine.stdout == ourStatusLine, comment)
        #expect(sandbox.exists(sandbox.statusLineLatest), comment)
    }

    /// Runs a hook and a status line, and checks that nothing under the home changed and nothing
    /// was printed.
    func expectSilent(_ sandbox: Sandbox, _ comment: Comment? = nil) throws {
        let before = sandbox.snapshot()
        let hook = try runBridge("hook", stdin: try hookPayload(event: "Stop"), in: sandbox)
        #expect(hook.status == 0)
        #expect(hook.stdout == "")
        let statusLine = try runBridge("statusline", stdin: try fixtureText("statusline-payload.json"), in: sandbox)
        #expect(statusLine.status == 0)
        #expect(statusLine.stdout == "", comment)
        #expect(sandbox.snapshot() == before, comment)
    }

    // MARK: - Still installed

    @Test(arguments: Trace.allCases)
    func anyTraceOfTheAppKeepsTheBridgeWorking(trace: Trace) throws {
        let (sandbox, _) = try makeSandbox(with: [trace])
        try expectWorking(sandbox)
    }

    /// Installs made before bridge version 4 recorded no app: they work as before, whatever is installed.
    @Test func withoutARecordTheBridgeKeepsWorking() throws {
        let sandbox = try Sandbox()
        try sandbox.placeScriptCheckingSandboxApplications()
        try expectWorking(sandbox)
    }

    @Test func aNewlineAfterTheRecordedPathIsIgnored() throws {
        let (sandbox, app) = try makeSandbox(with: [.recordedApp])
        try sandbox.write(app.path + "\n", to: sandbox.appPath)
        try expectWorking(sandbox)
    }

    @Test func aRecordedPathWithSpacesAndQuotes() throws {
        let (sandbox, _) = try makeSandbox()
        let app = sandbox.scratch.appendingPathComponent("My \"dev\" builds/Head room $HOME.app", isDirectory: true)
        try sandbox.makeDirectory(app)
        try sandbox.write(app.path, to: sandbox.appPath)
        try expectWorking(sandbox)
    }

    // MARK: - Uninstalled

    @Test func goneOnceNoTraceOfTheAppIsLeft() throws {
        let (sandbox, _) = try makeSandbox()
        try expectSilent(sandbox)
    }

    /// Nothing is created, changed or deleted: not the session records SessionEnd would remove, not
    /// the old files SessionStart would prune.
    @Test(arguments: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd"])
    func hooksTouchNothing(event: String) throws {
        let (sandbox, _) = try makeSandbox()
        try sandbox.write("{}", to: sandbox.sessions.appendingPathComponent("\(sessionID).hook.json"))
        try sandbox.write("{}", to: sandbox.sessions.appendingPathComponent("\(sessionID).statusline.json"))
        let old = sandbox.sessions.appendingPathComponent("old-session.hook.json")
        try sandbox.write("{}", to: old)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-8 * 24 * 3600)], ofItemAtPath: old.path)
        let before = sandbox.snapshot()

        let result = try runBridge("hook", stdin: try hookPayload(event: event), in: sandbox)

        #expect(result.status == 0)
        #expect(result.stdout == "")
        #expect(sandbox.snapshot() == before)
    }

    @Test func theStatusLineIsTheUsersOwnAgain() throws {
        let (sandbox, _) = try makeSandbox()
        // The user's command still gets the payload.
        try sandbox.saveOriginalStatusLine(["type": "command", "command": #"printf 'mine: '; grep -o '"session_id"' | head -n 1"#])
        let before = sandbox.snapshot()

        let result = try runBridge("statusline", stdin: try fixtureText("statusline-payload.json"), in: sandbox)

        #expect(result.status == 0)
        #expect(result.stdout == "mine: \"session_id\"\n")
        #expect(sandbox.snapshot() == before)
    }

    @Test func withoutAStatusLineOfTheirOwnNothingIsPrinted() throws {
        let (sandbox, _) = try makeSandbox()
        try expectSilent(sandbox)
    }

    /// Only an absolute path can name the app; anything else in the record names nothing.
    @Test(arguments: ["", "\n", "Headroom.app", "DerivedData/Build/Products/Debug/Headroom.app", "~/Applications/Headroom.app"])
    func aRecordThatIsNoAbsolutePathNamesNoApp(record: String) throws {
        let (sandbox, _) = try makeSandbox(with: [.recordedApp])
        try sandbox.write(record, to: sandbox.appPath)
        try expectSilent(sandbox, "record \(record.debugDescription)")
    }

    /// A record that is not a regular file (a FIFO would block a read) names no app.
    @Test func aRecordThatIsNotAFileNamesNoAppAndDoesNotBlock() throws {
        let (sandbox, _) = try makeSandbox(with: [.recordedApp])
        try FileManager.default.removeItem(at: sandbox.appPath)
        try makeFIFO(at: sandbox.appPath)

        let result = finishes(within: 5, unblocking: [sandbox.appPath]) {
            (try? runBridge("hook", stdin: try hookPayload(event: "Stop"), in: sandbox))?.status
        }

        #expect(result == .some(0))
        #expect(!sandbox.exists(sandbox.sessions))
    }

    // MARK: - Installer

    @Test func connectRecordsTheAppBundle() throws {
        let sandbox = try Sandbox()
        let app = "/Applications/Headroom Beta.app"

        try BridgeInstaller(claudeDirectory: sandbox.claude, appBundlePath: app).install()

        #expect(try String(contentsOf: sandbox.appPath, encoding: .utf8) == app)
        let permissions = try FileManager.default.attributesOfItem(atPath: sandbox.appPath.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        #expect(sandbox.installer.state() == .installed)
    }

    /// Connecting from something that is not an app bundle records nothing, so the bridge it just
    /// connected keeps working; an older record naming another app goes.
    @Test func connectWithoutAnAppBundleRemovesAnOlderRecord() throws {
        let sandbox = try Sandbox()
        try BridgeInstaller(claudeDirectory: sandbox.claude, appBundlePath: "/gone/Headroom.app").install()
        #expect(sandbox.exists(sandbox.appPath))

        try BridgeInstaller(claudeDirectory: sandbox.claude, appBundlePath: nil).install()

        #expect(!sandbox.exists(sandbox.appPath))
        #expect(sandbox.installer.state() == .installed)
    }

    @Test func disconnectRemovesTheRecord() throws {
        let sandbox = try Sandbox()
        try BridgeInstaller(claudeDirectory: sandbox.claude, appBundlePath: "/Applications/Headroom.app").install()

        try sandbox.installer.uninstall()

        #expect(!sandbox.exists(sandbox.appPath))
        #expect(!sandbox.exists(sandbox.bridgeDirectory))
    }

    @Test(arguments: [
        ("/Applications/Headroom.app", "/Applications/Headroom.app"),
        ("/Users/me/code/headroom/build/DerivedData/Build/Products/Debug/Headroom.app",
         "/Users/me/code/headroom/build/DerivedData/Build/Products/Debug/Headroom.app"),
        ("/Applications/Xcode.app/Contents/Developer/usr/bin", nil),
        ("/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Xcode/Agents", nil),
        ("/usr/local/bin", nil),
        ("Headroom.app", nil),
        ("", nil),
    ] as [(String, String?)])
    func onlyAnAppBundleIsRecorded(bundlePath: String, recorded: String?) {
        #expect(BridgeInstaller.appBundlePath(fromBundlePath: bundlePath) == recorded)
    }

    @Test func theRunningAppIsRecordedByDefault() {
        let expected = BridgeInstaller.appBundlePath(fromBundlePath: Bundle.main.bundlePath)
        #expect(BridgeInstaller.runningAppBundlePath == expected)
        #expect(BridgeInstaller(claudeDirectory: URL(fileURLWithPath: "/tmp/x")).appBundlePath == expected)
        #expect(BridgeInstaller(paths: .standard(home: URL(fileURLWithPath: "/tmp/x"))).appBundlePath == expected)
    }

    /// Bridge version 4 is what records the app: a version 3 install reads as outdated, and
    /// updating it records the app.
    @Test func aVersion3InstallIsOutdatedAndUpdatingRecordsTheApp() throws {
        let sandbox = try Sandbox()
        try BridgeInstaller(claudeDirectory: sandbox.claude, appBundlePath: nil).install()
        let version3 = BridgeScript.contents.replacingOccurrences(of: "# headroom-bridge v\(BridgeScript.version)\n", with: "# headroom-bridge v3\n")
        try #require(version3 != BridgeScript.contents)
        try sandbox.write(version3, to: sandbox.script)
        #expect(sandbox.installer.state() == .outdated)

        try BridgeInstaller(claudeDirectory: sandbox.claude, appBundlePath: "/Applications/Headroom.app").install()

        #expect(sandbox.installer.state() == .installed)
        #expect(try String(contentsOf: sandbox.appPath, encoding: .utf8) == "/Applications/Headroom.app")
    }

    /// The whole story: connect from an app with the user's own status line, then delete the app.
    @Test func deletingTheAppSilencesTheConnectedBridge() throws {
        let sandbox = try Sandbox()
        try sandbox.writeSettings(#"{"statusLine":{"type":"command","command":"echo mine"}}"#)
        let app = sandbox.scratch.appendingPathComponent("Build/Headroom.app", isDirectory: true)
        try sandbox.makeDirectory(app)
        try BridgeInstaller(claudeDirectory: sandbox.claude, appBundlePath: app.path).install()
        try sandbox.placeScriptCheckingSandboxApplications()

        try runBridge("hook", stdin: try hookPayload(event: "Stop"), in: sandbox)
        #expect(sandbox.exists(sandbox.sessions.appendingPathComponent("\(sessionID).hook.json")))
        let connected = try runBridge("statusline", stdin: try fixtureText("statusline-payload.json"), in: sandbox)
        #expect(connected.stdout == "mine\n")
        #expect(sandbox.exists(sandbox.statusLineLatest))

        try FileManager.default.removeItem(at: app)
        let before = sandbox.snapshot()

        let other = "11111111-2222-3333-4444-555555555555"
        let hook = try runBridge("hook", stdin: try hookPayload(event: "UserPromptSubmit", sessionID: other), in: sandbox)
        let statusLine = try runBridge("statusline", stdin: try fixtureText("statusline-payload.json"), in: sandbox)

        #expect(hook.status == 0 && hook.stdout == "")
        #expect(statusLine.stdout == "mine\n")
        #expect(sandbox.snapshot() == before)
    }
}
