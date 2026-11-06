import Darwin
import Foundation

/// `~/.claude/settings.json`, read and written conservatively (spec §2.6).
///
/// Anything unexpected (invalid JSON, comments, a non-object top level, a `hooks` value of the
/// wrong shape) makes the file "unreadable": the installer then refuses to touch it.
/// A symlinked settings file is edited in place, so dotfile setups keep their link.
struct SettingsFile {
    /// A parsed settings file and the exact bytes it came from.
    struct Contents {
        var object: [String: Any]
        var data: Data
        var permissions: mode_t
    }

    static let maxSize = 8 * 1024 * 1024

    /// The configured path (may be a symlink).
    let url: URL

    /// The file holding the bytes.
    var resolvedURL: URL { url.resolvingSymlinksInPath() }

    /// True when `url` is a symbolic link (dangling or not).
    var isSymlink: Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK
    }

    /// The parsed file, or nil when there is none. Throws `settingsUnreadable` otherwise, or
    /// `settingsOutsideGrant` when it links to a file outside its folder that can't be opened.
    func read() throws -> Contents? {
        switch RegularFile.read(resolvedURL, maxSize: Self.maxSize) {
        case .success(let file):
            return Contents(object: try Self.parse(file.data), data: file.data, permissions: file.permissions)
        case .failure(.system(let code)) where code == ENOENT || code == ENOTDIR:
            if isSymlink { throw BridgeInstallError.settingsUnreadable("settings.json links to a missing file") }
            return nil
        case .failure(.system(let code)):
            // The sandboxed app may open only the folder the user granted (~/.claude), so a link into
            // ~/dotfiles fails with EPERM there. That is not something to fix in the file.
            if code == EPERM || code == EACCES, let target = linkTargetOutsideFolder() {
                throw BridgeInstallError.settingsOutsideGrant(target: target.path)
            }
            throw BridgeInstallError.settingsUnreadable("settings.json can't be read: \(String(cString: strerror(code)))")
        case .failure(.notRegular):
            throw BridgeInstallError.settingsUnreadable("settings.json is not a regular file")
        case .failure(.tooLarge(let size)):
            throw BridgeInstallError.settingsUnreadable("settings.json is unexpectedly large (\(size) bytes)")
        }
    }

    /// Where `url` links to when that is outside the folder holding it, else nil.
    private func linkTargetOutsideFolder() -> URL? {
        guard isSymlink, let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else {
            return nil
        }
        let folder = url.deletingLastPathComponent()
        // Follows further links as far as it may; a destination it can't look into stays as written.
        let target = URL(fileURLWithPath: destination, relativeTo: folder).standardizedFileURL.resolvingSymlinksInPath()
        // resolvingSymlinksInPath drops a leading /private only for paths it can see, so compare without it.
        func comparable(_ path: String) -> String { path.hasPrefix("/private/") ? String(path.dropFirst(8)) : path }
        let folders = [folder.standardizedFileURL, folder.resolvingSymlinksInPath()].map { comparable($0.path) + "/" }
        return folders.contains { comparable(target.path).hasPrefix($0) } ? nil : target
    }

    func write(_ object: [String: Any], permissions: mode_t) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw BridgeInstallError.writeFailed("the new settings can't be written as JSON")
        }
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        )
        try AtomicFile.write(data + Data("\n".utf8), to: resolvedURL, permissions: permissions)
    }

    static func parse(_ data: Data) throws -> [String: Any] {
        if data.allSatisfy({ [0x20, 0x09, 0x0A, 0x0D].contains($0) }) { return [:] }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else {
            throw BridgeInstallError.settingsUnreadable("settings.json is not valid JSON")
        }
        guard !hasKeysEqualAsSwiftStrings(parsed) else {
            throw BridgeInstallError.settingsUnreadable("settings.json has keys that differ only in Unicode normalization")
        }
        guard let object = parsed as? [String: Any] else {
            throw BridgeInstallError.settingsUnreadable("settings.json is not a JSON object")
        }
        if let hooks = object["hooks"] {
            guard let events = hooks as? [String: Any] else {
                throw BridgeInstallError.settingsUnreadable("\"hooks\" in settings.json is not an object")
            }
            for (event, groups) in events where !(groups is [Any]) {
                throw BridgeInstallError.settingsUnreadable("\"hooks.\(event)\" in settings.json is not a list")
            }
        }
        return object
    }

    /// True when some JSON object holds two keys that JSONSerialization keeps apart but Swift
    /// treats as equal (e.g. "café" in NFC and NFD): converting it to `[String: Any]` would
    /// silently drop one of them. JSONSerialization caps nesting at 512, so recursion is bounded.
    private static func hasKeysEqualAsSwiftStrings(_ value: Any) -> Bool {
        if let object = value as? NSDictionary {
            var keys = Set<String>()
            for (key, child) in object {
                guard let key = key as? String, keys.insert(key).inserted else { return true }
                if hasKeysEqualAsSwiftStrings(child) { return true }
            }
        } else if let array = value as? NSArray {
            return array.contains { hasKeysEqualAsSwiftStrings($0) }
        }
        return false
    }
}
