#if HEADROOM_COPILOT_CLI
import Foundation
import HeadroomModel
import Testing
@testable import SetupKit

/// "Connect Copilot CLI" and "Disconnect" (1.1 §4.9) against a temp home: exactly `hooks/headroom.json` and
/// `headroom/` are written and removed, and nothing else in `~/.copilot` changes.
@Suite("CopilotBridgeInstaller")
struct CopilotBridgeInstallerTests {
    let appPath = "/Applications/Headroom Debug.app"

    /// A sandbox with a `~/.copilot` holding files of the user's and Copilot CLI's own, which must never change.
    func makeSandbox() throws -> Sandbox {
        let sandbox = try Sandbox()
        try sandbox.write(#"{"hooks":{"sessionStart":[{"type":"command","bash":"echo mine"}]},"version":1}"#, to: sandbox.copilot.appendingPathComponent("hooks/mine.json"))
        try sandbox.write(#"{"synthetic":"not read"}"#, to: sandbox.copilot.appendingPathComponent("config.json"))
        try sandbox.write("synthetic log\n", to: sandbox.copilotPaths.logsDirectory.appendingPathComponent("process-1790250000000-4242.log"))
        return sandbox
    }

    /// Everything under the home except Headroom's own two paths.
    func othersOf(_ sandbox: Sandbox) -> [String: Data?] {
        sandbox.snapshot().filter { path, _ in
            !path.hasPrefix("/.copilot/headroom") && path != "/.copilot/hooks/headroom.json"
        }
    }

    func hooksObject(_ sandbox: Sandbox) throws -> [String: Any] {
        try #require(try jsonObject(at: sandbox.copilotPaths.hooksFile) as? [String: Any])
    }

    // MARK: - Install

    @Test func installWritesTheHooksFileAndTheScript() throws {
        let sandbox = try makeSandbox()
        let others = othersOf(sandbox)
        let installer = sandbox.copilotInstaller()
        #expect(installer.state() == .notInstalled)

        try installer.install()

        #expect(installer.state() == .installed)
        let reference = #""$HOME/.copilot/headroom/bridge.sh""#
        #expect(try Data(contentsOf: sandbox.copilotPaths.hooksFile) == CopilotBridgeHooks.contents(scriptReference: reference))
        #expect(try String(contentsOf: sandbox.copilotScript, encoding: .utf8) == CopilotBridgeScript.contents)
        let files = FileManager.default
        #expect(try files.attributesOfItem(atPath: sandbox.copilotScript.path)[.posixPermissions] as? Int == 0o755)
        #expect(try files.attributesOfItem(atPath: sandbox.copilotPaths.bridgeDirectory.path)[.posixPermissions] as? Int == 0o700)
        #expect(!sandbox.exists(sandbox.copilotAppPath))
        #expect(othersOf(sandbox) == others)
    }

    @Test func hooksFileRegistersEveryEventButNeverPreToolUse() throws {
        let sandbox = try makeSandbox()
        try sandbox.copilotInstaller().install()
        let text = try String(contentsOf: sandbox.copilotPaths.hooksFile, encoding: .utf8)
        #expect(!text.contains("preToolUse"))
        #expect(!text.lowercased().contains("pretooluse"))

        let object = try hooksObject(sandbox)
        #expect(object["version"] as? Int == 1)
        let hooks = try #require(object["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(CopilotBridgeHooks.events))
        #expect(Set(hooks.keys) == [
            "sessionStart", "userPromptSubmitted", "postToolUse", "notification", "agentStop", "errorOccurred", "sessionEnd",
        ])
        for (event, value) in hooks {
            let entries = try #require(value as? [[String: Any]])
            #expect(entries.count == 1)
            let entry = try #require(entries.first)
            #expect(Set(entry.keys) == ["type", "bash", "timeoutSec"])
            #expect(entry["type"] as? String == "command")
            #expect(entry["timeoutSec"] as? Int == 5)
            #expect(entry["bash"] as? String
                == #"[ ! -f "$HOME/.copilot/headroom/bridge.sh" ] || exec /bin/bash "$HOME/.copilot/headroom/bridge.sh" hook \#(event)"#)
        }
    }

    @Test func eventsNeverIncludePreToolUse() {
        #expect(!CopilotBridgeHooks.events.contains("preToolUse"))
        let text = String(decoding: CopilotBridgeHooks.contents(scriptReference: "'/x/bridge.sh'"), as: UTF8.self)
        #expect(!text.contains("preToolUse"))
    }

    @Test func installRecordsTheAppAndRemovesAStaleRecord() throws {
        let sandbox = try makeSandbox()
        try sandbox.copilotInstaller(appBundlePath: appPath).install()
        #expect(try String(contentsOf: sandbox.copilotAppPath, encoding: .utf8) == appPath)
        #expect(sandbox.copilotInstaller(appBundlePath: appPath).state() == .installed)

        try sandbox.copilotInstaller(appBundlePath: nil).install()
        #expect(!sandbox.exists(sandbox.copilotAppPath))
    }

    @Test func installIsIdempotent() throws {
        let sandbox = try makeSandbox()
        let installer = sandbox.copilotInstaller(appBundlePath: appPath)
        try installer.install()
        let first = sandbox.snapshot()
        try installer.install()
        #expect(sandbox.snapshot() == first)
        #expect(installer.state() == .installed)
    }

    @Test func installKeepsSessionRecords() throws {
        let sandbox = try makeSandbox()
        let installer = sandbox.copilotInstaller()
        try installer.install()
        let record = sandbox.copilotSessions.appendingPathComponent("\(copilotSessionID).hook.json")
        try sandbox.write(#"{"v":1}"#, to: record)
        try installer.install()
        #expect(sandbox.exists(record))
    }

    @Test func installCreatesTheHooksFolderWhenMissing() throws {
        let sandbox = try Sandbox()
        try FileManager.default.createDirectory(at: sandbox.copilot, withIntermediateDirectories: true)
        try sandbox.copilotInstaller().install()
        #expect(sandbox.copilotInstaller().state() == .installed)
    }

    // MARK: - State and repair

    @Test func olderScriptReadsAsOutdatedAndInstallRepairsIt() throws {
        let sandbox = try makeSandbox()
        let installer = sandbox.copilotInstaller()
        try installer.install()
        try sandbox.write(
            CopilotBridgeScript.contents.replacingOccurrences(of: "# headroom-copilot-bridge v2", with: "# headroom-copilot-bridge v1"),
            to: sandbox.copilotScript
        )
        #expect(installer.state() == .outdated)
        try installer.install()
        #expect(installer.state() == .installed)
    }

    @Test func editedHooksFileReadsAsOutdated() throws {
        let sandbox = try makeSandbox()
        let installer = sandbox.copilotInstaller()
        try installer.install()
        var object = try hooksObject(sandbox)
        var hooks = try #require(object["hooks"] as? [String: Any])
        hooks.removeValue(forKey: "errorOccurred")
        object["hooks"] = hooks
        try sandbox.write(try jsonText(object), to: sandbox.copilotPaths.hooksFile)
        #expect(installer.state() == .outdated)

        try sandbox.write("{ not json", to: sandbox.copilotPaths.hooksFile)
        #expect(installer.state() == .outdated)
        try installer.install()
        #expect(installer.state() == .installed)
    }

    @Test func reformattedHooksFileIsStillCurrent() throws {
        let sandbox = try makeSandbox()
        let installer = sandbox.copilotInstaller()
        try installer.install()
        try sandbox.write(try jsonText(try hooksObject(sandbox)), to: sandbox.copilotPaths.hooksFile)
        #expect(installer.state() == .installed)
    }

    @Test func missingPiecesReadAsOutdated() throws {
        let sandbox = try makeSandbox()
        let installer = sandbox.copilotInstaller()
        try installer.install()
        try FileManager.default.removeItem(at: sandbox.copilotScript)
        #expect(installer.state() == .outdated)

        try installer.install()
        try FileManager.default.removeItem(at: sandbox.copilotPaths.hooksFile)
        #expect(installer.state() == .outdated)
    }

    @Test func onlySessionRecordsLeftReadsAsNotInstalledWithLeftovers() throws {
        let sandbox = try makeSandbox()
        let installer = sandbox.copilotInstaller()
        #expect(!installer.hasLeftoverFiles())
        try sandbox.write(#"{"v":1}"#, to: sandbox.copilotSessions.appendingPathComponent("x.hook.json"))
        #expect(installer.state() == .notInstalled)
        #expect(installer.hasLeftoverFiles())
    }

    @Test func missingCopilotFolderReadsAsNotInstalled() throws {
        let sandbox = try Sandbox()
        #expect(sandbox.copilotInstaller().state() == .notInstalled)
    }

    @Test func hooksFileThatIsAFolderReadsAsUnreadable() throws {
        let sandbox = try makeSandbox()
        try sandbox.makeDirectory(sandbox.copilotPaths.hooksFile)
        guard case .unreadable = sandbox.copilotInstaller().state() else {
            Issue.record("expected .unreadable, got \(sandbox.copilotInstaller().state())")
            return
        }
    }

    @Test func unreadableHooksFolderReadsAsUnreadable() throws {
        let sandbox = try makeSandbox()
        try sandbox.copilotInstaller().install()
        let hooks = sandbox.copilotPaths.hooksDirectory
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: hooks.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hooks.path) }
        guard case .unreadable(let reason) = sandbox.copilotInstaller().state() else {
            Issue.record("expected .unreadable, got \(sandbox.copilotInstaller().state())")
            return
        }
        #expect(reason.contains("~/.copilot/hooks/headroom.json"))
    }

    // MARK: - Uninstall

    @Test func uninstallRemovesExactlyWhatInstallAdded() throws {
        let sandbox = try makeSandbox()
        let before = sandbox.snapshot()
        // No app recorded: the bridge then writes whatever this machine's /Applications holds.
        let installer = sandbox.copilotInstaller()
        try installer.install()
        try runCopilotBridge(event: "sessionStart", fixture: "copilot-sessionStart.json", in: sandbox)
        #expect(sandbox.copilotRecordExists())

        try installer.uninstall()

        #expect(sandbox.snapshot() == before)
        #expect(installer.state() == .notInstalled)
        #expect(!installer.hasLeftoverFiles())
        #expect(sandbox.entries(in: sandbox.copilot, prefix: ".headroom-removing-").isEmpty)
    }

    @Test func uninstallWithNothingInstalledChangesNothing() throws {
        let sandbox = try makeSandbox()
        let before = sandbox.snapshot()
        try sandbox.copilotInstaller().uninstall()
        #expect(sandbox.snapshot() == before)
    }

    @Test func uninstallDeletesCopiesAnEarlierDisconnectLeft() throws {
        let sandbox = try makeSandbox()
        let leftover = sandbox.copilot.appendingPathComponent(".headroom-removing-EARLIER", isDirectory: true)
        try sandbox.write("{}", to: leftover.appendingPathComponent("sessions/a.hook.json"))
        let installer = sandbox.copilotInstaller()
        #expect(installer.hasLeftoverFiles())
        #expect(installer.uninstallPlan().map(\.action) == [.remove])
        try installer.uninstall()
        #expect(!sandbox.exists(leftover))
        #expect(!installer.hasLeftoverFiles())
    }

    @Test func uninstallWinsAgainstBridgeRunsStillWriting() throws {
        let sandbox = try makeSandbox()
        let installer = sandbox.copilotInstaller()
        try installer.install()
        try sandbox.makeDirectory(sandbox.copilotSessions)
        let writers = PathWriters(directories: [sandbox.copilotSessions], threads: 4)
        defer { writers.stop() }
        try installer.uninstall()
        #expect(!sandbox.exists(sandbox.copilotPaths.bridgeDirectory))
        #expect(!sandbox.exists(sandbox.copilotPaths.hooksFile))
    }

    // MARK: - Plans

    @Test func installPlanListsEveryChange() throws {
        let sandbox = try Sandbox()
        try FileManager.default.createDirectory(at: sandbox.copilot, withIntermediateDirectories: true)
        let installer = sandbox.copilotInstaller(appBundlePath: appPath)

        let fresh = installer.installPlan()
        #expect(fresh.map(\.action) == [.create, .create, .create, .create, .create])
        #expect(fresh.map(\.path) == [
            "~/.copilot/hooks/", "~/.copilot/headroom/", "~/.copilot/headroom/bridge.sh", "~/.copilot/headroom/app-path",
            "~/.copilot/hooks/headroom.json",
        ])
        let hooksDetail = try #require(fresh.last?.detail)
        for event in CopilotBridgeHooks.events { #expect(hooksDetail.contains(event)) }
        #expect(!hooksDetail.contains("preToolUse"))

        try installer.install()
        let repair = installer.installPlan()
        #expect(repair.map(\.action) == [.replace, .replace, .replace])
        #expect(repair.map(\.path) == ["~/.copilot/headroom/bridge.sh", "~/.copilot/headroom/app-path", "~/.copilot/hooks/headroom.json"])

        #expect(sandbox.copilotInstaller(appBundlePath: nil).installPlan().map(\.path) == [
            "~/.copilot/headroom/bridge.sh", "~/.copilot/hooks/headroom.json",
        ])
    }

    @Test func uninstallPlanListsWhatIsThere() throws {
        let sandbox = try makeSandbox()
        let installer = sandbox.copilotInstaller()
        #expect(installer.uninstallPlan().isEmpty)
        try installer.install()
        let plan = installer.uninstallPlan()
        #expect(plan.map(\.action) == [.remove, .remove])
        #expect(plan.map(\.path) == ["~/.copilot/hooks/headroom.json", "~/.copilot/headroom/"])
    }

    // MARK: - A folder picked for COPILOT_HOME

    @Test func customFolderUsesItsAbsolutePath() throws {
        let sandbox = try Sandbox()
        let folder = sandbox.scratch.appendingPathComponent("copilot home", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let installer = CopilotBridgeInstaller(copilotDirectory: folder, home: sandbox.home, appBundlePath: nil)
        #expect(installer.installPlan().last?.path == folder.appendingPathComponent("hooks/headroom.json").path)

        try installer.install()
        #expect(installer.state() == .installed)
        let text = try String(contentsOf: installer.paths.hooksFile, encoding: .utf8)
        #expect(!text.contains("$HOME"))
        #expect(text.contains("'\(installer.paths.bridgeScriptFile.path)'"))

        try installer.uninstall()
        #expect(installer.state() == .notInstalled)
        #expect(!sandbox.exists(installer.paths.bridgeDirectory))
    }

    @Test func scriptReferenceQuotesSingleQuotes() {
        let paths = CopilotPaths(copilotDirectory: URL(fileURLWithPath: "/Volumes/it's here/.copilot", isDirectory: true))
        #expect(CopilotBridgeHooks.scriptReference(paths: paths, home: URL(fileURLWithPath: "/Users/me"))
            == #"'/Volumes/it'\''s here/.copilot/headroom/bridge.sh'"#)
        #expect(CopilotBridgeHooks.scriptReference(paths: .standard(home: URL(fileURLWithPath: "/Users/me")), home: URL(fileURLWithPath: "/Users/me"))
            == #""$HOME/.copilot/headroom/bridge.sh""#)
    }
}
#endif
