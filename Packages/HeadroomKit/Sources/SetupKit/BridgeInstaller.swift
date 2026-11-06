import Darwin
import Foundation
import HeadroomModel

/// "Connect terminal" (spec §2.6): wires the bridge into `~/.claude/settings.json` and writes
/// `~/.claude/headroom/bridge.sh`; "Disconnect terminal" removes exactly that again.
///
/// settings.json is always read and validated before anything is written: when it can't be
/// parsed, `install()` and `uninstall()` throw `settingsUnreadable` and change nothing.
/// Unrelated keys and hooks keep their values (the file is rewritten with sorted keys).
public struct BridgeInstaller: Sendable {
    /// `~/.claude`
    public let claudeDirectory: URL
    /// The absolute path of the app bundle connecting the terminal, recorded in `appPathFile` by
    /// `install()`: once neither it, /Applications/Headroom.app nor the App Store container exists,
    /// the bridge knows Headroom is gone and stops writing. Nil (or empty) records nothing, and
    /// `install()` removes an older record.
    public let appBundlePath: String?

    /// `appBundlePath` defaults to the running app's bundle (nil outside an app, as in tests).
    public init(claudeDirectory: URL, appBundlePath: String? = BridgeInstaller.runningAppBundlePath) {
        self.claudeDirectory = claudeDirectory
        self.appBundlePath = appBundlePath
    }

    public init(paths: ClaudePaths, appBundlePath: String? = BridgeInstaller.runningAppBundlePath) {
        self.init(claudeDirectory: paths.claudeDirectory, appBundlePath: appBundlePath)
    }

    /// `Bundle.main`'s path when the running process is an app bundle, else nil.
    public static var runningAppBundlePath: String? {
        appBundlePath(fromBundlePath: Bundle.main.bundlePath)
    }

    /// `bundlePath` when it is an absolute path to an `.app` bundle, else nil: a command-line tool's
    /// "bundle" is just the folder it runs from.
    static func appBundlePath(fromBundlePath bundlePath: String) -> String? {
        bundlePath.hasPrefix("/") && bundlePath.hasSuffix(".app") ? bundlePath : nil
    }

    /// Each command does nothing when the script is missing (settings.json can reach a machine
    /// without it, through dotfiles say, and Claude Code would report a hook error in every session),
    /// and otherwise hands the shell over to the bridge, so the bridge's parent is Claude Code.
    public static let statusLineCommand =
        #"[ ! -f "$HOME/.claude/headroom/bridge.sh" ] || exec /bin/bash "$HOME/.claude/headroom/bridge.sh" statusline"#
    public static let hookCommand =
        #"[ ! -f "$HOME/.claude/headroom/bridge.sh" ] || exec /bin/bash "$HOME/.claude/headroom/bridge.sh" hook"#
    /// One hook group is added per event (spec §2.5, §2.6); the tool events also get
    /// `"matcher": ""`. `PostToolUse` (bridge version 2) clears "needs you" once a permission
    /// prompt is approved.
    public static let hookEvents = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd",
    ]
    /// Events whose hook group carries `"matcher": ""` (match every tool).
    static let matcherEvents: Set<String> = ["PreToolUse", "PostToolUse"]

    public var settingsFile: URL { claudeDirectory.appendingPathComponent("settings.json") }
    /// The settings file as it was before the first install; never overwritten.
    public var backupFile: URL { claudeDirectory.appendingPathComponent("settings.json.headroom-backup") }
    public var bridgeDirectory: URL { claudeDirectory.appendingPathComponent("headroom", isDirectory: true) }
    public var scriptFile: URL { bridgeDirectory.appendingPathComponent("bridge.sh") }
    /// The user's own status line, restored on uninstall.
    public var originalStatusLineFile: URL { bridgeDirectory.appendingPathComponent("original-statusline.json") }
    /// Its command, byte for byte, which the bridge chains (no JSON to decode in bash).
    public var originalStatusLineCommandFile: URL { bridgeDirectory.appendingPathComponent("original-statusline.cmd") }
    /// `appBundlePath`, as the bridge reads it (bridge version 4).
    public var appPathFile: URL { bridgeDirectory.appendingPathComponent("app-path") }

    /// Hidden siblings `~/.claude/headroom` is renamed to while `uninstall()` deletes it.
    static let removalPrefix = ".headroom-removing-"

    private var settings: SettingsFile { SettingsFile(url: settingsFile) }

    // MARK: - State

    public func state() -> BridgeInstallState {
        let object: [String: Any]
        do {
            object = try settings.read()?.object ?? [:]
        } catch let error as BridgeInstallError {
            return .settingsUnreadable(error.unreadableReason ?? String(describing: error))
        } catch {
            return .settingsUnreadable(String(describing: error))
        }
        guard BridgeEntries.hasAny(in: object) else { return .notInstalled }
        let hooks = object["hooks"] as? [String: Any] ?? [:]
        let complete = BridgeEntries.isCurrentStatusLine(object["statusLine"])
            && Self.hookEvents.allSatisfy { BridgeEntries.isCurrent(hooks[$0] as? [Any], event: $0) }
        guard complete, let version = installedScriptVersion(), version >= BridgeScript.version else {
            return .outdated
        }
        return .installed
    }

    /// True when `~/.claude/headroom` is on disk, or a copy of it that Disconnect couldn't finish
    /// deleting. With `state() == .notInstalled` these are leftovers (session records, the last rate
    /// limits) that `uninstall()` deletes, so Disconnect should stay available for them.
    public func hasLeftoverFiles() -> Bool {
        var info = stat()
        return lstat(bridgeDirectory.path, &info) == 0 || !interruptedRemovals().isEmpty
    }

    // MARK: - Install

    public func install() throws {
        let current = try settings.read()
        var object = current?.object ?? [:]

        let existingStatusLine = object["statusLine"]
        let replacesTheirs = existingStatusLine != nil && !BridgeEntries.isOurStatusLine(existingStatusLine)
        // Over our own entry, the user's status line is the one saved when they first connected.
        let original = replacesTheirs ? existingStatusLine : existingStatusLine == nil ? nil : savedStatusLine()
        object["statusLine"] = BridgeEntries.statusLine(keepingOptionsOf: original, existingStatusLine)

        var hooks = object["hooks"] as? [String: Any] ?? [:]
        for event in Self.hookEvents {
            let groups = hooks[event] as? [Any] ?? []
            guard !BridgeEntries.isCurrent(groups, event: event) else { continue }
            hooks[event] = BridgeEntries.removingOurHooks(from: groups) + [BridgeEntries.hookGroup(for: event)]
        }
        object["hooks"] = hooks

        try performWrites {
            let files = FileManager.default
            // Only the original is backed up: a file that already holds our entries (one an
            // earlier install created, say) is not what the user had before connecting.
            if let current, !files.fileExists(atPath: backupFile.path), !BridgeEntries.hasAny(in: current.object) {
                try AtomicFile.write(current.data, to: backupFile, permissions: current.permissions)
            }
            try files.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
            if !files.fileExists(atPath: bridgeDirectory.path) {
                try files.createDirectory(at: bridgeDirectory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            }
            try AtomicFile.write(Data(BridgeScript.contents.utf8), to: scriptFile, permissions: 0o755)
            // Without an app to name, an older record (of another copy, since deleted) must not
            // silence the bridge this install just connected.
            if let appBundlePath, !appBundlePath.isEmpty {
                try AtomicFile.write(Data(appBundlePath.utf8), to: appPathFile, permissions: 0o600)
            } else if files.fileExists(atPath: appPathFile.path) {
                try files.removeItem(at: appPathFile)
            }

            if replacesTheirs, let existingStatusLine {
                try AtomicFile.write(try Self.jsonData(existingStatusLine), to: originalStatusLineFile, permissions: 0o600)
            } else if existingStatusLine == nil, files.fileExists(atPath: originalStatusLineFile.path) {
                // Left over from an install whose status line the user has since removed.
                try files.removeItem(at: originalStatusLineFile)
            }
            // Also written when updating: versions before 3 saved only the JSON.
            if let original {
                try saveOriginalCommand(of: original)
            } else if !files.fileExists(atPath: originalStatusLineFile.path),
                      files.fileExists(atPath: originalStatusLineCommandFile.path) {
                try files.removeItem(at: originalStatusLineCommandFile)
            }

            if let current, jsonValuesEqual(object, current.object) { return }
            try settings.write(object, permissions: current?.permissions ?? 0o644)
        }
    }

    // MARK: - Uninstall

    public func uninstall() throws {
        let current = try settings.read()
        try performWrites {
            let files = FileManager.default
            if let current, let restored = removingOurEntries(from: current.object) {
                // No backup means there was no settings file before the first install (or it
                // already held our entries, so there was no original to keep).
                if restored.isEmpty, !files.fileExists(atPath: backupFile.path), !settings.isSymlink {
                    try files.removeItem(at: settingsFile)
                } else {
                    try settings.write(restored, permissions: current.permissions)
                }
            }
            try deleteBridgeFiles()
        }
    }

    /// Deletes `~/.claude/headroom`, renaming it to a hidden sibling first so that its path is gone
    /// at once: bridge runs still in flight (running sessions keep calling it until they reload their
    /// settings) then can't write into it while it is deleted, and the bridge never creates the
    /// folder itself. Copies that an earlier Disconnect couldn't delete go too.
    private func deleteBridgeFiles() throws {
        var doomed = interruptedRemovals().map { ($0, "~/.claude/\($0.lastPathComponent), left over from an earlier Disconnect") }
        let renamed = claudeDirectory.appendingPathComponent(Self.removalPrefix + UUID().uuidString)
        if Darwin.rename(bridgeDirectory.path, renamed.path) == 0 {
            doomed.append((renamed, "~/.claude/headroom (now ~/.claude/\(renamed.lastPathComponent))"))
        } else if errno != ENOENT {
            doomed.append((bridgeDirectory, "~/.claude/headroom"))
        }
        let failures = doomed.compactMap { url, name in Self.deleteTree(at: url).map { "\(name): \($0)" } }
        if !failures.isEmpty {
            throw BridgeInstallError.writeFailed("Headroom couldn't delete \(failures.joined(separator: "; "))")
        }
    }

    /// Deletes `url` and everything in it, without following links. Nil when it's gone, else why not.
    /// Only "directory not empty" is retried: a bridge run that was still writing into it.
    private static func deleteTree(at url: URL) -> String? {
        var code: Int32 = 0
        for attempt in 0..<5 {
            if attempt > 0 { usleep(50_000) }
            if removefile(url.path, nil, removefile_flags_t(REMOVEFILE_RECURSIVE)) == 0 { return nil }
            code = errno
            if code == ENOENT { return nil }
            if code != ENOTEMPTY { break }
        }
        return code == ENOTEMPTY
            ? "a running Claude Code session kept writing to it. Try again in a moment."
            : String(cString: strerror(code))
    }

    /// Hidden copies of `~/.claude/headroom` that an earlier `uninstall()` couldn't finish deleting.
    private func interruptedRemovals() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: claudeDirectory.path)) ?? []
        return names.filter { $0.hasPrefix(Self.removalPrefix) }.sorted().map { claudeDirectory.appendingPathComponent($0) }
    }

    /// The settings without our entries (groups, events and `hooks` we emptied are dropped,
    /// the original status line comes back), or nil when there was nothing of ours.
    /// An event list or `hooks` object that was already empty in the original settings (the
    /// backup) is kept empty, so the result is value-equal to what the user had.
    private func removingOurEntries(from settings: [String: Any]) -> [String: Any]? {
        var object = settings
        var changed = false
        let keepEmpty = originallyEmptyHookContainers()
        if BridgeEntries.isOurStatusLine(object["statusLine"]) {
            if let original = savedStatusLine() {
                object["statusLine"] = original
            } else {
                object.removeValue(forKey: "statusLine")
            }
            changed = true
        }
        if var hooks = object["hooks"] as? [String: Any] {
            var removedAny = false
            for (event, value) in hooks {
                guard let groups = value as? [Any], BridgeEntries.ourHookCount(in: groups) > 0 else { continue }
                let kept = BridgeEntries.removingOurHooks(from: groups)
                if kept.isEmpty, !keepEmpty.events.contains(event) {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = kept
                }
                removedAny = true
            }
            if removedAny {
                if hooks.isEmpty, !keepEmpty.hooks {
                    object.removeValue(forKey: "hooks")
                } else {
                    object["hooks"] = hooks
                }
                changed = true
            }
        }
        return changed ? object : nil
    }

    // MARK: - Helpers

    /// Whether the backed-up original had an empty `hooks` object, and which events it had
    /// as empty lists. Nothing when there is no readable backup.
    private func originallyEmptyHookContainers() -> (hooks: Bool, events: Set<String>) {
        guard case .success(let file) = RegularFile.read(backupFile, maxSize: SettingsFile.maxSize),
              let original = try? SettingsFile.parse(file.data),
              let hooks = original["hooks"] as? [String: Any]
        else { return (false, []) }
        let emptyEvents = hooks.compactMap { event, groups in (groups as? [Any])?.isEmpty == true ? event : nil }
        return (hooks.isEmpty, Set(emptyEvents))
    }

    private func savedStatusLine() -> Any? {
        guard case .success(let file) = RegularFile.read(originalStatusLineFile, maxSize: SettingsFile.maxSize),
              let value = try? JSONSerialization.jsonObject(with: file.data, options: [.fragmentsAllowed]),
              !BridgeEntries.isOurStatusLine(value)
        else { return nil }
        return value
    }

    /// Saves the command of the user's status line for the bridge to run as is: settings.json may
    /// escape control characters (`\u001b` for colors) that bash would otherwise have to decode.
    private func saveOriginalCommand(of statusLine: Any) throws {
        if let command = (statusLine as? [String: Any])?["command"] as? String, !command.isEmpty {
            try AtomicFile.write(Data(command.utf8), to: originalStatusLineCommandFile, permissions: 0o600)
        } else if FileManager.default.fileExists(atPath: originalStatusLineCommandFile.path) {
            try FileManager.default.removeItem(at: originalStatusLineCommandFile)
        }
    }

    private func installedScriptVersion() -> Int? {
        guard case .success(let head) = RegularFile.prefix(of: scriptFile, count: 4096) else { return nil }
        return BridgeScript.headerVersion(in: String(decoding: head, as: UTF8.self))
    }

    private static func jsonData(_ value: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject([value]) else {
            throw BridgeInstallError.writeFailed("the existing status line can't be saved as JSON")
        }
        let data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed, .sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        )
        return data + Data("\n".utf8)
    }

    /// Runs file operations, reporting any failure as `writeFailed`.
    private func performWrites(_ body: () throws -> Void) throws {
        do {
            try body()
        } catch let error as BridgeInstallError {
            throw error
        } catch let error as AtomicFile.Failure {
            throw BridgeInstallError.writeFailed(error.description)
        } catch {
            throw BridgeInstallError.writeFailed(error.localizedDescription)
        }
    }
}
