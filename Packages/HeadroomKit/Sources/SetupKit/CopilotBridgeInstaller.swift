#if HEADROOM_COPILOT_CLI
import Darwin
import Foundation
import HeadroomModel

/// Whether "Connect Copilot CLI" is in place (1.1 §4.9).
public enum CopilotBridgeState: Sendable, Equatable {
    case notInstalled
    /// The hooks file is current and the script's version is at least `CopilotBridgeScript.version`.
    case installed
    /// Some of it is there but not current: an older script, an edited or partial hooks file, or a missing piece.
    case outdated
    /// The Copilot folder or the hooks file can't be read; the message says why.
    case unreadable(String)
}

public enum CopilotBridgeError: Error, Equatable {
    case writeFailed(String)
}

extension CopilotBridgeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .writeFailed(let reason): reason
        }
    }
}

/// One change "Connect Copilot CLI" or "Disconnect" makes, for the confirmation dialog, which lists every change
/// before anything is written (1.1 §4.9).
public struct CopilotBridgeChange: Sendable, Equatable {
    public enum Action: String, Sendable, Equatable {
        case create, replace, remove
    }

    public var action: Action
    /// The path as the dialog shows it: `~/.copilot/hooks/headroom.json`, or absolute outside the home folder.
    public var path: String
    /// What it is, in one sentence.
    public var detail: String

    public init(action: Action, path: String, detail: String) {
        self.action = action
        self.path = path
        self.detail = detail
    }
}

/// "Connect Copilot CLI" (1.1 §4.9, mirroring 1.0 §2.6): writes `hooks/headroom.json` and `headroom/bridge.sh` into
/// the granted Copilot folder; "Disconnect" removes exactly those two again. Every path comes from `CopilotPaths`,
/// and nothing else in the folder is opened: the only other access is listing the folder's names, to find
/// `headroom` copies an earlier Disconnect couldn't finish deleting.
public struct CopilotBridgeInstaller: Sendable {
    public let paths: CopilotPaths
    /// The user's real home folder, to show paths as `~/…` and to tell the standard `~/.copilot` from a folder
    /// picked for `COPILOT_HOME` (`CopilotBridgeHooks.scriptReference`).
    public let home: URL
    /// The absolute path of the app bundle connecting, recorded in `appPathFile`: once neither it,
    /// /Applications/Headroom.app nor the App Store container exists, the bridge knows Headroom is gone and stops
    /// writing. Nil (or empty) records nothing, and `install()` removes an older record.
    public let appBundlePath: String?

    /// `appBundlePath` defaults to the running app's bundle (nil outside an app, as in tests).
    public init(paths: CopilotPaths, home: URL = RealHome.url, appBundlePath: String? = BridgeInstaller.runningAppBundlePath) {
        self.paths = paths
        self.home = home
        self.appBundlePath = appBundlePath
    }

    public init(
        copilotDirectory: URL,
        home: URL = RealHome.url,
        appBundlePath: String? = BridgeInstaller.runningAppBundlePath
    ) {
        self.init(paths: CopilotPaths(copilotDirectory: copilotDirectory), home: home, appBundlePath: appBundlePath)
    }

    /// `headroom/app-path`: `appBundlePath`, as the bridge reads it.
    public var appPathFile: URL { paths.bridgeDirectory.appendingPathComponent("app-path") }

    /// Hidden siblings `headroom/` is renamed to while `uninstall()` deletes it.
    static let removalPrefix = ".headroom-removing-"
    /// Hooks files are a few kilobytes; anything past this isn't the one Headroom wrote.
    static let maxHooksFileSize = 1 << 20

    /// How the hook commands name the script.
    var scriptReference: String { CopilotBridgeHooks.scriptReference(paths: paths, home: home) }

    // MARK: - State

    public func state() -> CopilotBridgeState {
        var hooksCurrent = false
        let hooksPresent: Bool
        switch RegularFile.read(paths.hooksFile, maxSize: Self.maxHooksFileSize) {
        case .success(let file):
            hooksPresent = true
            hooksCurrent = CopilotBridgeHooks.isCurrent(file.data, scriptReference: scriptReference)
        case .failure(.system(ENOENT)), .failure(.system(ENOTDIR)):
            hooksPresent = false
        case .failure(.tooLarge):
            hooksPresent = true
        case .failure(.notRegular):
            return .unreadable("\(display(paths.hooksFile)) isn't a file")
        case .failure(.system(let code)):
            return .unreadable("Headroom can't read \(display(paths.hooksFile)): \(String(cString: strerror(code)))")
        }
        let scriptPresent = exists(paths.bridgeScriptFile)
        guard hooksPresent || scriptPresent else { return .notInstalled }
        guard hooksCurrent, let version = installedScriptVersion(), version >= CopilotBridgeScript.version else {
            return .outdated
        }
        return .installed
    }

    /// True when `headroom/` is on disk, or a copy of it that Disconnect couldn't finish deleting. With
    /// `state() == .notInstalled` these are leftovers (session records) that `uninstall()` deletes, so Disconnect
    /// should stay available for them.
    public func hasLeftoverFiles() -> Bool {
        exists(paths.bridgeDirectory) || !interruptedRemovals().isEmpty
    }

    // MARK: - Plans

    /// What `install()` would change now, in the order it writes.
    public func installPlan() -> [CopilotBridgeChange] {
        var changes: [CopilotBridgeChange] = []
        if !exists(paths.hooksDirectory) {
            changes.append(.init(action: .create, path: display(paths.hooksDirectory) + "/", detail: "Copilot CLI's folder for user hooks."))
        }
        if !exists(paths.bridgeDirectory) {
            changes.append(.init(
                action: .create, path: display(paths.bridgeDirectory) + "/",
                detail: "Headroom's folder: the script and one small record per session (its id, folder and status, never your prompts)."
            ))
        }
        changes.append(.init(
            action: exists(paths.bridgeScriptFile) ? .replace : .create, path: display(paths.bridgeScriptFile),
            detail: "The script the hooks run. It saves each session's status and prints nothing."
        ))
        if let appBundlePath, !appBundlePath.isEmpty {
            changes.append(.init(
                action: exists(appPathFile) ? .replace : .create, path: display(appPathFile),
                detail: "Where this copy of Headroom is, so the script stops writing once Headroom is deleted."
            ))
        }
        changes.append(.init(
            action: exists(paths.hooksFile) ? .replace : .create, path: display(paths.hooksFile),
            detail: "Runs the script on \(Self.list(CopilotBridgeHooks.events)). Your other hooks and settings stay as they are."
        ))
        return changes
    }

    /// What `uninstall()` would remove now.
    public func uninstallPlan() -> [CopilotBridgeChange] {
        var changes: [CopilotBridgeChange] = []
        if exists(paths.hooksFile) {
            changes.append(.init(action: .remove, path: display(paths.hooksFile), detail: "Headroom's hooks."))
        }
        if hasLeftoverFiles() {
            changes.append(.init(
                action: .remove, path: display(paths.bridgeDirectory) + "/",
                detail: "The script and the session records."
            ))
        }
        return changes
    }

    // MARK: - Install

    /// Writes the script first and the hooks file last, so the hooks never name a script that isn't there yet.
    public func install() throws {
        try performWrites {
            let files = FileManager.default
            try files.createDirectory(at: paths.hooksDirectory, withIntermediateDirectories: true)
            if !exists(paths.bridgeDirectory) {
                try files.createDirectory(
                    at: paths.bridgeDirectory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
                )
            }
            try AtomicFile.write(Data(CopilotBridgeScript.contents.utf8), to: paths.bridgeScriptFile, permissions: 0o755)
            // Without an app to name, an older record (of another copy, since deleted) must not silence the bridge
            // this install just connected.
            if let appBundlePath, !appBundlePath.isEmpty {
                try AtomicFile.write(Data(appBundlePath.utf8), to: appPathFile, permissions: 0o600)
            } else if exists(appPathFile) {
                try files.removeItem(at: appPathFile)
            }
            try AtomicFile.write(
                CopilotBridgeHooks.contents(scriptReference: scriptReference), to: paths.hooksFile, permissions: 0o644
            )
        }
    }

    // MARK: - Uninstall

    /// Removes the hooks file, then `headroom/`: it is first renamed to a hidden sibling so that its path is gone at
    /// once. Copilot CLI sessions that are already running keep calling the hook commands until they end; those runs
    /// then find no script, or a script whose folder is gone, and write nothing. Copies that an earlier Disconnect
    /// couldn't delete go too.
    public func uninstall() throws {
        try performWrites {
            if unlink(paths.hooksFile.path) != 0 {
                let code = errno
                if code != ENOENT, code != ENOTDIR {
                    throw CopilotBridgeError.writeFailed(
                        "Headroom couldn't remove \(display(paths.hooksFile)): \(String(cString: strerror(code)))"
                    )
                }
            }
            try deleteBridgeFiles()
        }
    }

    private func deleteBridgeFiles() throws {
        var doomed = interruptedRemovals().map { ($0, "\(display($0)), left over from an earlier Disconnect") }
        let renamed = paths.copilotDirectory.appendingPathComponent(Self.removalPrefix + UUID().uuidString)
        if Darwin.rename(paths.bridgeDirectory.path, renamed.path) == 0 {
            doomed.append((renamed, "\(display(paths.bridgeDirectory)) (now \(display(renamed)))"))
        } else if errno != ENOENT {
            doomed.append((paths.bridgeDirectory, display(paths.bridgeDirectory)))
        }
        let failures = doomed.compactMap { url, name in Self.deleteTree(at: url).map { "\(name): \($0)" } }
        if !failures.isEmpty {
            throw CopilotBridgeError.writeFailed("Headroom couldn't delete \(failures.joined(separator: "; "))")
        }
    }

    /// Deletes `url` and everything in it, without following links. Nil when it's gone, else why not. Only
    /// "directory not empty" is retried: a bridge run that was still writing into it.
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
            ? "a running Copilot CLI session kept writing to it. Try again in a moment."
            : String(cString: strerror(code))
    }

    /// Hidden copies of `headroom/` that an earlier `uninstall()` couldn't finish deleting.
    private func interruptedRemovals() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: paths.copilotDirectory.path)) ?? []
        return names.filter { $0.hasPrefix(Self.removalPrefix) }.sorted().map { paths.copilotDirectory.appendingPathComponent($0) }
    }

    // MARK: - Helpers

    private func installedScriptVersion() -> Int? {
        guard case .success(let head) = RegularFile.prefix(of: paths.bridgeScriptFile, count: 4096) else { return nil }
        return CopilotBridgeScript.headerVersion(in: String(decoding: head, as: UTF8.self))
    }

    /// Whether anything is at `url`, a dangling symbolic link included.
    private func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    /// `url` as `~/…` when it is inside the home folder, else its absolute path.
    func display(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        guard path.hasPrefix(homePath + "/") else { return path }
        return "~" + path.dropFirst(homePath.count)
    }

    /// "A, B and C".
    static func list(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        let rest = items.dropLast()
        return rest.isEmpty ? last : rest.joined(separator: ", ") + " and " + last
    }

    /// Runs file operations, reporting any failure as `writeFailed`.
    private func performWrites(_ body: () throws -> Void) throws {
        do {
            try body()
        } catch let error as CopilotBridgeError {
            throw error
        } catch let error as AtomicFile.Failure {
            throw CopilotBridgeError.writeFailed(error.description)
        } catch {
            throw CopilotBridgeError.writeFailed(error.localizedDescription)
        }
    }
}
#endif
