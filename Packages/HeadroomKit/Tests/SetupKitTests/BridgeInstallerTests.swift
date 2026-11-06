import Foundation
import Testing
@testable import SetupKit

@Suite("BridgeInstaller")
struct BridgeInstallerTests {
    /// A missing script makes each command a no-op (settings.json can reach machines without it),
    /// and the shell hands over to the bridge so its parent stays Claude Code.
    let ourStatusLine: [String: Any] = [
        "type": "command",
        "command": #"[ ! -f "$HOME/.claude/headroom/bridge.sh" ] || exec /bin/bash "$HOME/.claude/headroom/bridge.sh" statusline"#,
    ]
    let ourHook: [String: Any] = [
        "type": "command",
        "command": #"[ ! -f "$HOME/.claude/headroom/bridge.sh" ] || exec /bin/bash "$HOME/.claude/headroom/bridge.sh" hook"#,
        "timeout": 5,
    ]
    /// What versions 1 and 2 of the bridge installed.
    let legacyStatusLine: [String: Any] = [
        "type": "command",
        "command": #"/bin/bash "$HOME/.claude/headroom/bridge.sh" statusline"#,
    ]
    let legacyHook: [String: Any] = [
        "type": "command",
        "command": #"/bin/bash "$HOME/.claude/headroom/bridge.sh" hook"#,
        "timeout": 5,
    ]
    /// Spec §2.5: `PostToolUse` clears "needs you" after a permission prompt is approved.
    let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd"]
    /// What version 1 of the bridge installed.
    let version1Events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SessionEnd"]

    /// Spec §2.6: both tool events also get `"matcher": ""`.
    func ourGroup(_ event: String) -> [String: Any] {
        group(event, ourHook)
    }

    func group(_ event: String, _ hook: [String: Any]) -> [String: Any] {
        ["PreToolUse", "PostToolUse"].contains(event) ? ["matcher": "", "hooks": [hook]] : ["hooks": [hook]]
    }

    /// How many of our hook entries each event holds.
    func ourHookCounts(_ settings: [String: Any]) -> [String: Int] {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        var counts: [String: Int] = [:]
        for (event, groups) in hooks {
            for group in groups as? [[String: Any]] ?? [] {
                for hook in group["hooks"] as? [[String: Any]] ?? [] where jsonEqual(hook, ourHook) {
                    counts[event, default: 0] += 1
                }
            }
        }
        return counts
    }

    func settingsWithStatusLine() throws -> [String: Any] {
        var settings = try #require(try parseJSON(try fixtureText("settings-user.json")) as? [String: Any])
        settings["statusLine"] = ["type": "command", "command": #"~/bin/my-status.sh --color "always""#, "padding": 1]
        return settings
    }

    // MARK: - Install

    @Test func commandsMatchTheSpec() {
        #expect(BridgeInstaller.statusLineCommand == ourStatusLine["command"] as? String)
        #expect(BridgeInstaller.hookCommand == ourHook["command"] as? String)
        #expect(BridgeInstaller.hookEvents == events)
    }

    @Test func freshInstallCreatesSettingsAndScript() throws {
        let sandbox = try Sandbox()

        try sandbox.installer.install()

        let settings = try sandbox.settingsObject()
        #expect(Set(settings.keys) == ["statusLine", "hooks"])
        #expect(jsonEqual(settings["statusLine"], ourStatusLine))
        let hooks = try #require(settings["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(events))
        for event in events {
            #expect(jsonEqual(hooks[event], [ourGroup(event)]), "\(event)")
        }
        #expect(try String(contentsOf: sandbox.script, encoding: .utf8) == BridgeScript.contents)
        let permissions = try FileManager.default.attributesOfItem(atPath: sandbox.script.path)[.posixPermissions] as? Int
        #expect(permissions == 0o755)
        #expect(!sandbox.exists(sandbox.backup))
        #expect(!sandbox.exists(sandbox.originalStatusLine))
        #expect(sandbox.installer.state() == .installed)
    }

    @Test func writesSortedPrettyJSONWithUnescapedSlashes() throws {
        let sandbox = try Sandbox()
        try sandbox.installer.install()
        let text = try String(contentsOf: sandbox.settings, encoding: .utf8)
        #expect(text.contains(#""command" : "\/bin\/bash"#) == false)
        #expect(text.contains(#"/bin/bash \"$HOME/.claude/headroom/bridge.sh\" statusline"#))
        #expect(text.contains("\n  \"hooks\" : {"))
        let hooksIndex = try #require(text.range(of: "\"hooks\""))
        let statusIndex = try #require(text.range(of: "\"statusLine\""))
        #expect(hooksIndex.lowerBound < statusIndex.lowerBound)
    }

    @Test func installPreservesUnrelatedKeysAndUserHooks() throws {
        let sandbox = try Sandbox()
        try sandbox.writeSettings(try fixtureText("settings-user.json"))
        let original = try sandbox.settingsObject()

        try sandbox.installer.install()

        let settings = try sandbox.settingsObject()
        #expect(Set(settings.keys) == Set(original.keys).union(["statusLine"]))
        for (key, value) in original where key != "hooks" {
            #expect(jsonEqual(settings[key], value), "\(key)")
        }
        let before = try #require(original["hooks"] as? [String: Any])
        let after = try #require(settings["hooks"] as? [String: Any])
        #expect(Set(after.keys) == Set(before.keys).union(events))
        for event in Set(after.keys) {
            let userGroups = before[event] as? [Any] ?? []
            let expected = events.contains(event) ? userGroups + [ourGroup(event)] : userGroups
            #expect(jsonEqual(after[event], expected), "\(event)")
        }
        #expect(sandbox.installer.state() == .installed)
    }

    @Test func backupIsWrittenOnceAndNeverOverwritten() throws {
        let sandbox = try Sandbox()
        let firstText = try fixtureText("settings-user.json")
        try sandbox.writeSettings(firstText)

        try sandbox.installer.install()
        #expect(try Data(contentsOf: sandbox.backup) == Data(firstText.utf8))

        var changed = try sandbox.settingsObject()
        changed["laterSetting"] = true
        try sandbox.writeSettings(try jsonText(changed, pretty: true))
        try sandbox.installer.install()
        try sandbox.installer.uninstall()
        try sandbox.installer.install()

        #expect(try Data(contentsOf: sandbox.backup) == Data(firstText.utf8))
    }

    @Test func existingStatusLineIsSavedAndChained() throws {
        let sandbox = try Sandbox()
        let command = #"cat > "$HOME/chained-stdin.json"; printf '%s' 'mine: "quoted" \ back'"#
        var original = try #require(try parseJSON(try fixtureText("settings-user.json")) as? [String: Any])
        let userStatusLine: [String: Any] = ["type": "command", "command": command, "padding": 0]
        original["statusLine"] = userStatusLine
        try sandbox.writeSettings(try jsonText(original, pretty: true))

        try sandbox.installer.install()

        #expect(jsonEqual(try jsonObject(at: sandbox.originalStatusLine), userStatusLine))
        #expect(try String(contentsOf: sandbox.originalStatusLineCommand, encoding: .utf8) == command)
        // The user's options stay on the entry that replaces theirs.
        #expect(jsonEqual(try sandbox.settingsObject()["statusLine"], ourStatusLine.merging(["padding": 0]) { $1 }))

        let payload = try fixtureText("statusline-payload.json")
        let result = try runBridge("statusline", stdin: payload, in: sandbox)
        #expect(result.stdout == #"mine: "quoted" \ back"#)
        #expect(try String(contentsOf: sandbox.home.appendingPathComponent("chained-stdin.json"), encoding: .utf8) == payload)
        #expect(sandbox.exists(sandbox.statusLineLatest))
    }

    /// Claude Code re-runs a status line every `refreshInterval` seconds; dropping it would freeze a
    /// chained clock until the next event. The other options keep their meaning too.
    @Test func statusLineOptionsCarryOverToOurEntry() throws {
        let sandbox = try Sandbox()
        let userStatusLine: [String: Any] = [
            "type": "command", "command": "date +%T", "refreshInterval": 1, "padding": 0, "hideVimModeIndicator": true,
        ]
        try sandbox.writeSettings(try jsonText(["model": "opus", "statusLine": userStatusLine], pretty: true))

        try sandbox.installer.install()

        let expected = ourStatusLine.merging(["refreshInterval": 1, "padding": 0, "hideVimModeIndicator": true]) { $1 }
        #expect(jsonEqual(try sandbox.settingsObject()["statusLine"], expected))
        #expect(sandbox.installer.state() == .installed)
        let installed = try Data(contentsOf: sandbox.settings)
        try sandbox.installer.install()
        #expect(try Data(contentsOf: sandbox.settings) == installed)

        try sandbox.installer.uninstall()
        #expect(jsonEqual(try sandbox.settingsObject(), ["model": "opus", "statusLine": userStatusLine]))
    }

    @Test func optionsAddedToOurEntryKeepItCurrent() throws {
        let sandbox = try Sandbox()
        try sandbox.installer.install()
        var settings = try sandbox.settingsObject()
        settings["statusLine"] = ourStatusLine.merging(["refreshInterval": 5]) { $1 }
        try sandbox.writeSettings(try jsonText(settings, pretty: true))

        #expect(sandbox.installer.state() == .installed)
        try sandbox.installer.install()
        #expect(jsonEqual(try sandbox.settingsObject()["statusLine"], ourStatusLine.merging(["refreshInterval": 5]) { $1 }))
    }

    /// settings.json may escape control characters (`\u001b` for colors); the bridge must run the
    /// command with the real bytes, exactly as Claude Code would without Headroom.
    @Test func chainedCommandKeepsControlCharacters() throws {
        let sandbox = try Sandbox()
        let command = "printf '%s|' 'ff\u{0C}x' 'bs\u{08}x' 'nl\nx' 'u\u{7F}\u{1F}'; printf '\u{1B}[1;32m%s\u{1B}[0m' ok"
        try sandbox.writeSettings(#"{"statusLine": {"type": "command", "command": \#(try jsonText(command))}}"#)
        let direct = try runShellCommand(command, stdin: "{}", in: sandbox).run.stdout

        try sandbox.installer.install()
        let chained = try runBridge("statusline", stdin: try fixtureText("statusline-payload.json"), in: sandbox)

        #expect(direct == "ff\u{0C}x|bs\u{08}x|nl\nx|u\u{7F}\u{1F}|\u{1B}[1;32mok\u{1B}[0m")
        #expect(chained.stdout == direct)
        let permissions = try FileManager.default.attributesOfItem(atPath: sandbox.originalStatusLineCommand.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    /// Versions 1 and 2 saved the original status line only as JSON. Updating also saves its command
    /// for the new script, keeps chaining it, and still restores it on Disconnect.
    @Test func updatingAnOlderInstallKeepsChainingTheSavedStatusLine() throws {
        let sandbox = try Sandbox()
        let command = "printf '\u{1B}[31m%s\u{1B}[0m' mine"
        let userStatusLine: [String: Any] = ["type": "command", "command": command, "refreshInterval": 2]
        try installVersion1(in: sandbox, over: try jsonText(["statusLine": userStatusLine]))
        try sandbox.write(try jsonText(userStatusLine, pretty: true), to: sandbox.originalStatusLine)
        #expect(sandbox.installer.state() == .outdated)

        try sandbox.installer.install()

        #expect(sandbox.installer.state() == .installed)
        #expect(try String(contentsOf: sandbox.originalStatusLineCommand, encoding: .utf8) == command)
        // The options the older install dropped come back from the saved original.
        #expect(jsonEqual(try sandbox.settingsObject()["statusLine"], ourStatusLine.merging(["refreshInterval": 2]) { $1 }))
        let chained = try runBridge("statusline", stdin: try fixtureText("statusline-payload.json"), in: sandbox)
        #expect(chained.stdout == "\u{1B}[31mmine\u{1B}[0m")
        try sandbox.installer.uninstall()
        #expect(jsonEqual(try sandbox.settingsObject(), ["statusLine": userStatusLine]))
    }

    @Test func removingTheStatusLineAndReconnectingStopsChaining() throws {
        let sandbox = try Sandbox()
        try sandbox.writeSettings(try jsonText(try settingsWithStatusLine(), pretty: true))
        try sandbox.installer.install()
        #expect(sandbox.exists(sandbox.originalStatusLineCommand))
        var settings = try sandbox.settingsObject()
        settings.removeValue(forKey: "statusLine")
        try sandbox.writeSettings(try jsonText(settings, pretty: true))

        try sandbox.installer.install()

        #expect(!sandbox.exists(sandbox.originalStatusLine))
        #expect(!sandbox.exists(sandbox.originalStatusLineCommand))
        let result = try runBridge("statusline", stdin: try fixtureText("statusline-payload.json"), in: sandbox)
        #expect(result.stdout == "5h 20% · wk 90% · ctx 26%\n")
    }

    @Test func installIsIdempotent() throws {
        let sandbox = try Sandbox()
        try sandbox.writeSettings(try jsonText(try settingsWithStatusLine(), pretty: true))

        try sandbox.installer.install()
        let first = try Data(contentsOf: sandbox.settings)
        let firstOriginal = try Data(contentsOf: sandbox.originalStatusLine)
        try sandbox.installer.install()
        try sandbox.installer.install()

        #expect(try Data(contentsOf: sandbox.settings) == first)
        #expect(try Data(contentsOf: sandbox.originalStatusLine) == firstOriginal)
        #expect(ourHookCounts(try sandbox.settingsObject()) == Dictionary(uniqueKeysWithValues: events.map { ($0, 1) }))
        #expect(sandbox.installer.state() == .installed)
    }

    @Test func scriptVersionIsFive() {
        // Version 2 added the PostToolUse hook; version 3 never recreates ~/.claude/headroom, cleans
        // up its temp files and chains the saved command byte for byte; version 4 goes quiet once
        // Headroom is uninstalled (app-path); version 5 checks the container of the release bundle
        // ID. Older installs read as outdated.
        #expect(BridgeScript.version == 5)
        #expect(BridgeScript.headerVersion(in: BridgeScript.contents) == 5)
    }

    @Test func scriptChecksTheReleaseContainer() {
        #expect(BridgeScript.containerPath == "Library/Containers/com.niomartinez.headroom")
        #expect(BridgeScript.contents.contains("$HOME/Library/Containers/com.niomartinez.headroom"))
        #expect(!BridgeScript.contents.contains("com.antoniomartinez"))
    }

    /// What "Connect terminal" wrote before PostToolUse was added: the version 1 hook set with its
    /// unguarded commands, a version 1 script, and a backup of the user's original settings.
    func installVersion1(in sandbox: Sandbox, over userText: String) throws {
        try sandbox.write(userText, to: sandbox.backup)
        var settings = try #require(try parseJSON(userText) as? [String: Any])
        settings["statusLine"] = legacyStatusLine
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in version1Events {
            hooks[event] = (hooks[event] as? [Any] ?? []) + [group(event, legacyHook)]
        }
        settings["hooks"] = hooks
        try sandbox.writeSettings(try jsonText(settings, pretty: true))
        let script = BridgeScript.contents.replacingOccurrences(
            of: "# headroom-bridge v\(BridgeScript.version)", with: "# headroom-bridge v1"
        )
        try sandbox.write(script, to: sandbox.script)
    }

    @Test func aVersion1InstallIsOutdatedAndUpgradesInPlace() throws {
        let sandbox = try Sandbox()
        let userText = try fixtureText("settings-user.json")
        let original = try #require(try parseJSON(userText) as? [String: Any])
        try installVersion1(in: sandbox, over: userText)
        #expect(sandbox.installer.state() == .outdated)

        try sandbox.installer.install()

        #expect(sandbox.installer.state() == .installed)
        let settings = try sandbox.settingsObject()
        #expect(ourHookCounts(settings) == Dictionary(uniqueKeysWithValues: events.map { ($0, 1) }))
        let hooks = try #require(settings["hooks"] as? [String: Any])
        let before = try #require(original["hooks"] as? [String: Any])
        for event in events {
            let userGroups = before[event] as? [Any] ?? []
            #expect(jsonEqual(hooks[event], userGroups + [ourGroup(event)]), "\(event)")
        }
        let script = try String(contentsOf: sandbox.script, encoding: .utf8)
        #expect(BridgeScript.headerVersion(in: script) == BridgeScript.version)
        #expect(try Data(contentsOf: sandbox.backup) == Data(userText.utf8))

        // Upgrading again changes nothing more.
        let upgraded = try Data(contentsOf: sandbox.settings)
        try sandbox.installer.install()
        #expect(try Data(contentsOf: sandbox.settings) == upgraded)

        try sandbox.installer.uninstall()
        #expect(jsonEqual(try sandbox.settingsObject(), original))
        #expect(sandbox.installer.state() == .notInstalled)
    }

    @Test func version1HooksWithTheCurrentScriptAreOutdated() throws {
        let sandbox = try Sandbox()
        try installVersion1(in: sandbox, over: "{}")
        try sandbox.placeScript()
        #expect(sandbox.installer.state() == .outdated)

        try sandbox.installer.install()

        #expect(sandbox.installer.state() == .installed)
        #expect(ourHookCounts(try sandbox.settingsObject()) == Dictionary(uniqueKeysWithValues: events.map { ($0, 1) }))
    }

    @Test func uninstallRemovesOurPostToolUseHookAndKeepsTheUsers() throws {
        let sandbox = try Sandbox()
        let userText = try fixtureText("settings-user.json")
        let originalHooks = try #require((try parseJSON(userText) as? [String: Any])?["hooks"] as? [String: Any])
        try sandbox.writeSettings(userText)
        try sandbox.installer.install()
        let installed = try #require(try sandbox.settingsObject()["hooks"] as? [String: Any])
        #expect(jsonEqual(installed["PostToolUse"], (originalHooks["PostToolUse"] as? [Any] ?? []) + [ourGroup("PostToolUse")]))

        try sandbox.installer.uninstall()

        let hooks = try #require(try sandbox.settingsObject()["hooks"] as? [String: Any])
        #expect(jsonEqual(hooks["PostToolUse"], originalHooks["PostToolUse"]))
        #expect(ourHookCounts(try sandbox.settingsObject()).isEmpty)
    }

    @Test func reinstallRepairsDuplicatedAndEditedEntries() throws {
        let sandbox = try Sandbox()
        try sandbox.installer.install()
        var settings = try sandbox.settingsObject()
        var hooks = try #require(settings["hooks"] as? [String: Any])
        hooks["Stop"] = [ourGroup("Stop"), ourGroup("Stop")]
        hooks["Notification"] = [["hooks": [["type": "command", "command": #"/bin/bash "$HOME/.claude/headroom/bridge.sh" hook"#, "timeout": 30]]]]
        hooks.removeValue(forKey: "SessionEnd")
        settings["hooks"] = hooks
        try sandbox.writeSettings(try jsonText(settings, pretty: true))
        #expect(sandbox.installer.state() == .outdated)

        try sandbox.installer.install()

        #expect(ourHookCounts(try sandbox.settingsObject()) == Dictionary(uniqueKeysWithValues: events.map { ($0, 1) }))
        let repaired = try #require(try sandbox.settingsObject()["hooks"] as? [String: Any])
        #expect(jsonEqual(repaired["Notification"], [ourGroup("Notification")]))
        #expect(sandbox.installer.state() == .installed)
    }

    @Test func installKeepsASymlinkedSettingsFileLinked() throws {
        let sandbox = try Sandbox()
        let target = sandbox.home.appendingPathComponent("dotfiles/claude-settings.json")
        try sandbox.write(try fixtureText("settings-user.json"), to: target)
        try FileManager.default.createDirectory(at: sandbox.claude, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: sandbox.settings, withDestinationURL: target)
        let original = try jsonObject(at: target)

        try sandbox.installer.install()

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: sandbox.settings.path) == target.path)
        #expect(jsonEqual((try jsonObject(at: target) as? [String: Any])?["statusLine"], ourStatusLine))
        #expect(sandbox.installer.state() == .installed)

        try sandbox.installer.uninstall()

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: sandbox.settings.path) == target.path)
        #expect(jsonEqual(try jsonObject(at: target), original))
    }

    @Test func installKeepsTheSettingsFilePermissions() throws {
        let sandbox = try Sandbox()
        try sandbox.writeSettings("{\"model\":\"opus\"}")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sandbox.settings.path)

        try sandbox.installer.install()

        let permissions = try FileManager.default.attributesOfItem(atPath: sandbox.settings.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    // MARK: - Uninstall

    static let uninstallCases: [String] = [
        "settings-user.json",
        "with-status-line",
        "{}",
        #"{"model":"sonnet","hooks":{"PostToolUse":[{"matcher":"Write","hooks":[{"type":"command","command":"echo hi"}]}]}}"#,
        #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"},{"type":"command","command":"echo 2"}]}]}}"#,
        // Containers the user already had empty come back as they were.
        #"{"hooks":{}}"#,
        #"{"model":"sonnet","hooks":{"Stop":[],"SessionEnd":[],"PostToolUse":[{"matcher":"Write","hooks":[{"type":"command","command":"echo hi"}]}]}}"#,
    ]

    @Test(arguments: uninstallCases)
    func uninstallRestoresTheOriginalSettings(source: String) throws {
        let sandbox = try Sandbox()
        let text: String = switch source {
        case "settings-user.json": try fixtureText(source)
        case "with-status-line": try jsonText(try settingsWithStatusLine(), pretty: true)
        default: source
        }
        try sandbox.writeSettings(text)
        let original = try parseJSON(text)

        try sandbox.installer.install()
        try sandbox.installer.install()
        try sandbox.installer.uninstall()

        #expect(jsonEqual(try jsonObject(at: sandbox.settings), original))
        #expect(!sandbox.exists(sandbox.bridgeDirectory))
        #expect(sandbox.exists(sandbox.backup))
        #expect(sandbox.installer.state() == .notInstalled)
    }

    @Test func uninstallAfterAFreshInstallRemovesTheSettingsFileItCreated() throws {
        let sandbox = try Sandbox()
        try sandbox.installer.install()
        try sandbox.installer.uninstall()
        #expect(!sandbox.exists(sandbox.settings))
        #expect(!sandbox.exists(sandbox.bridgeDirectory))
        #expect(sandbox.installer.state() == .notInstalled)
    }

    /// Reinstalling (e.g. repairing after an update) over a settings file that the first install
    /// created must not back up that file: it already holds our entries, so it is not the original.
    @Test func backupNeverHoldsOurOwnEntries() throws {
        let sandbox = try Sandbox()
        try sandbox.installer.install()
        var settings = try sandbox.settingsObject()
        settings["model"] = "opus"
        var hooks = try #require(settings["hooks"] as? [String: Any])
        hooks.removeValue(forKey: "Stop")
        settings["hooks"] = hooks
        try sandbox.writeSettings(try jsonText(settings, pretty: true))

        try sandbox.installer.install()

        if sandbox.exists(sandbox.backup) {
            let backup = try String(contentsOf: sandbox.backup, encoding: .utf8)
            #expect(!backup.contains(".claude/headroom/bridge.sh"))
        }
        try sandbox.installer.uninstall()
        #expect(jsonEqual(try sandbox.settingsObject(), ["model": "opus"]))

        // A file that holds nothing but our entries is removed again, as after a single install.
        let fresh = try Sandbox()
        try fresh.installer.install()
        try fresh.installer.install()
        try fresh.installer.uninstall()
        #expect(!fresh.exists(fresh.settings))
        #expect(!fresh.exists(fresh.backup))
    }

    @Test func uninstallKeepsSettingsTheUserAddedAfterInstalling() throws {
        let sandbox = try Sandbox()
        try sandbox.writeSettings(try fixtureText("settings-user.json"))
        try sandbox.installer.install()
        var settings = try sandbox.settingsObject()
        settings["addedLater"] = ["a": 1]
        var hooks = try #require(settings["hooks"] as? [String: Any])
        var stop = try #require(hooks["Stop"] as? [Any])
        stop.append(["hooks": [["type": "command", "command": "echo later"]]])
        hooks["Stop"] = stop
        settings["hooks"] = hooks
        try sandbox.writeSettings(try jsonText(settings, pretty: true))

        try sandbox.installer.uninstall()

        let after = try sandbox.settingsObject()
        #expect(jsonEqual(after["addedLater"], ["a": 1]))
        #expect(after["statusLine"] == nil)
        let afterStop = (after["hooks"] as? [String: Any])?["Stop"] as? [Any]
        #expect(afterStop?.count == 2)
        #expect(ourHookCounts(after).isEmpty)
    }

    @Test func uninstallRestoresAStatusLineTheUserSetAfterInstalling() throws {
        let sandbox = try Sandbox()
        try sandbox.writeSettings("{}")
        try sandbox.installer.install()
        var settings = try sandbox.settingsObject()
        let theirs: [String: Any] = ["type": "command", "command": "echo newer"]
        settings["statusLine"] = theirs
        try sandbox.writeSettings(try jsonText(settings, pretty: true))
        #expect(sandbox.installer.state() == .outdated)

        try sandbox.installer.install()
        #expect(jsonEqual(try jsonObject(at: sandbox.originalStatusLine), theirs))
        try sandbox.installer.uninstall()

        #expect(jsonEqual(try sandbox.settingsObject(), ["statusLine": theirs]))
    }

    @Test func uninstallLeavesAForeignStatusLineAlone() throws {
        let sandbox = try Sandbox()
        try sandbox.writeSettings(try jsonText(try settingsWithStatusLine(), pretty: true))
        try sandbox.installer.install()
        var settings = try sandbox.settingsObject()
        let theirs: [String: Any] = ["type": "command", "command": "echo replaced by hand"]
        settings["statusLine"] = theirs
        try sandbox.writeSettings(try jsonText(settings, pretty: true))

        try sandbox.installer.uninstall()

        #expect(jsonEqual(try sandbox.settingsObject()["statusLine"], theirs))
    }

    @Test func uninstallWhenNotInstalledChangesNothing() throws {
        let sandbox = try Sandbox()
        let text = try fixtureText("settings-user.json")
        try sandbox.writeSettings(text)

        try sandbox.installer.uninstall()

        #expect(try Data(contentsOf: sandbox.settings) == Data(text.utf8))
        #expect(!sandbox.exists(sandbox.backup))
        #expect(!sandbox.exists(sandbox.bridgeDirectory))

        let empty = try Sandbox()
        try empty.installer.uninstall()
        #expect(!empty.exists(empty.claude))
    }

    // MARK: - Unreadable settings

    @Test(arguments: [
        #"{"model": "opus",, }"#,
        #"{"model": "opus"} // comment"#,
        "[1, 2]",
        #""just a string""#,
        #"{"hooks": "not an object"}"#,
        #"{"hooks": {"Stop": {"hooks": []}}}"#,
        "\u{FEFF}\u{0}{",
        // Distinct JSON keys that are equal as Swift strings (NFC vs NFD): converting would drop one.
        "{\"caf\u{E9}\": 1, \"cafe\u{301}\": 2}",
        "{\"hooks\": {\"St\u{F6}p\": [], \"Sto\u{308}p\": []}}",
    ])
    func unreadableSettingsThrowAndWriteNothing(text: String) throws {
        let sandbox = try Sandbox()
        try sandbox.writeSettings(text)
        let before = sandbox.snapshot()

        let installError = #expect(throws: BridgeInstallError.self) { try sandbox.installer.install() }
        let uninstallError = #expect(throws: BridgeInstallError.self) { try sandbox.installer.uninstall() }

        #expect(sandbox.snapshot() == before)
        for error in [installError, uninstallError] {
            guard case .settingsUnreadable(let reason)? = error else {
                Issue.record("expected settingsUnreadable, got \(String(describing: error))")
                continue
            }
            #expect(!reason.isEmpty)
        }
        guard case .settingsUnreadable(let reason) = sandbox.installer.state() else {
            Issue.record("expected settingsUnreadable, got \(sandbox.installer.state())")
            return
        }
        #expect(!reason.isEmpty)
    }

    @Test func corruptingAfterInstallBlocksUninstall() throws {
        let sandbox = try Sandbox()
        try sandbox.installer.install()
        try sandbox.writeSettings("{ broken")
        let before = sandbox.snapshot()

        #expect(throws: BridgeInstallError.self) { try sandbox.installer.uninstall() }

        #expect(sandbox.snapshot() == before)
        #expect(sandbox.exists(sandbox.script))
    }

    @Test func emptySettingsFileCountsAsEmptyObject() throws {
        let sandbox = try Sandbox()
        try sandbox.writeSettings("  \n")
        #expect(sandbox.installer.state() == .notInstalled)
        try sandbox.installer.install()
        #expect(sandbox.installer.state() == .installed)
        #expect(try Data(contentsOf: sandbox.backup) == Data("  \n".utf8))
    }

    // MARK: - State

    @Test func stateTransitions() throws {
        let sandbox = try Sandbox()
        let installer = sandbox.installer
        #expect(installer.state() == .notInstalled)

        try sandbox.writeSettings(try fixtureText("settings-user.json"))
        #expect(installer.state() == .notInstalled)

        try installer.install()
        #expect(installer.state() == .installed)

        // An older script header.
        let old = BridgeScript.contents.replacingOccurrences(
            of: "# headroom-bridge v\(BridgeScript.version)", with: "# headroom-bridge v\(BridgeScript.version - 1)"
        )
        try sandbox.write(old, to: sandbox.script)
        #expect(installer.state() == .outdated)
        try installer.install()
        #expect(installer.state() == .installed)

        // The script is gone.
        try FileManager.default.removeItem(at: sandbox.script)
        #expect(installer.state() == .outdated)
        try installer.install()
        #expect(installer.state() == .installed)

        // One hook entry was removed by hand.
        var settings = try sandbox.settingsObject()
        var hooks = try #require(settings["hooks"] as? [String: Any])
        hooks.removeValue(forKey: "UserPromptSubmit")
        settings["hooks"] = hooks
        try sandbox.writeSettings(try jsonText(settings, pretty: true))
        #expect(installer.state() == .outdated)
        try installer.install()
        #expect(installer.state() == .installed)

        // Only our status line is left.
        settings = try sandbox.settingsObject()
        settings.removeValue(forKey: "hooks")
        try sandbox.writeSettings(try jsonText(settings, pretty: true))
        #expect(installer.state() == .outdated)
        try installer.install()

        try installer.uninstall()
        #expect(installer.state() == .notInstalled)

        try sandbox.writeSettings("{ nope")
        guard case .settingsUnreadable = installer.state() else {
            Issue.record("expected settingsUnreadable")
            return
        }
    }

    @Test func aScriptAloneIsNotAnInstall() throws {
        let sandbox = try Sandbox()
        try sandbox.placeScript()
        try sandbox.writeSettings("{}")
        #expect(sandbox.installer.state() == .notInstalled)
    }
}
