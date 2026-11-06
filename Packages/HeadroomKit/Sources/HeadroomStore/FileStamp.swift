import Darwin
import Foundation

/// What a poller can cheaply learn about a file's content without reading it: size, modification time
/// (nanoseconds) and inode, so a file replaced by `mv` is noticed even if size and mtime happen to match.
///
/// Read with `stat(2)`, which follows symlinks like the kits' readers do. Never `URL.resourceValues`: it caches
/// per URL and returns a stale mtime in a long-lived poller without a run loop (spec §4).
struct FileStamp: Equatable, Sendable {
    var size: Int64
    var modifiedSeconds: Int
    var modifiedNanoseconds: Int
    var inode: UInt64

    /// Nil when nothing exists at `path` (or it can't be examined).
    static func of(path: String) -> FileStamp? {
        guard !path.isEmpty, !path.utf8.contains(0) else { return nil }
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return FileStamp(
            size: Int64(info.st_size),
            modifiedSeconds: Int(info.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int(info.st_mtimespec.tv_nsec),
            inode: UInt64(info.st_ino)
        )
    }

    static func of(_ url: URL) -> FileStamp? {
        of(path: url.path)
    }
}

/// The stamps of the files in one directory whose names pass a filter. Hidden files are left out, as the
/// SessionKit readers skip them too (the bridge writes `.<name>.<pid>.tmp` before moving a file into place).
struct DirectoryStamp: Equatable, Sendable {
    var files: [String: FileStamp]

    /// Nil when the directory can't be listed (missing or unreadable): nothing to compare, so read again.
    /// Lists the directory the same way the readers do, through any symlink.
    static func of(directory: URL, including include: (String) -> Bool) -> DirectoryStamp? {
        let path = directory.resolvingSymlinksInPath().path
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return nil }
        var files: [String: FileStamp] = [:]
        for name in names where !name.hasPrefix(".") && include(name) {
            // A file that vanished since the listing is simply left out; the next poll's listing agrees.
            files[name] = FileStamp.of(path: (path as NSString).appendingPathComponent(name))
        }
        return DirectoryStamp(files: files)
    }
}
