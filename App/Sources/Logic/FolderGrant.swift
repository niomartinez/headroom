import Darwin
import Foundation

/// Validates the folder a user picked in the access open panel.
enum FolderGrant {
    /// `true` when `chosen` is exactly the folder Headroom asked for, comparing standardized paths
    /// and, failing that, symlink-resolved paths (a `~/.claude` that links elsewhere). A parent
    /// folder is rejected: Headroom asks for the narrowest grant it needs.
    static func isExpected(_ chosen: URL, expected: URL) -> Bool {
        if chosen.standardizedFileURL.path == expected.standardizedFileURL.path {
            return true
        }
        return chosen.resolvingSymlinksInPath().standardizedFileURL.path
            == expected.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// `isExpected`, or for Codex and Copilot CLI a folder that has one of the tool's `homeMarkers` subfolders: the
    /// user's `CODEX_HOME` or `COPILOT_HOME`, which a sandboxed app can't read from the environment (1.1 §3.1, §4.9).
    static func isAcceptable(_ chosen: URL, for folder: HeadroomFolder, expected: URL? = nil) -> Bool {
        if isExpected(chosen, expected: expected ?? folder.expectedURL) { return true }
        return folder.homeMarkers.contains { isDirectory(chosen.appendingPathComponent($0, isDirectory: true)) }
    }

    /// An existing directory (symlinks followed); only `stat`ed, never opened.
    private static func isDirectory(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            var info = stat()
            return stat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
        }
    }
}
