import Darwin
import Foundation

/// A file's identity and state from `stat(2)`: a rollout that only grew keeps its inode and has a bigger size
/// (1.1 §3.3).
struct FileSignature: Sendable, Equatable {
    var inode: UInt64
    var size: Int64
    var modified: Date
    var isRegularFile: Bool

    init(_ info: stat) {
        inode = UInt64(info.st_ino)
        size = Int64(info.st_size)
        modified = Date(
            timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9
        )
        isRegularFile = (info.st_mode & S_IFMT) == S_IFREG
    }

    init(inode: UInt64, size: Int64, modified: Date, isRegularFile: Bool = true) {
        self.inode = inode
        self.size = size
        self.modified = modified
        self.isRegularFile = isRegularFile
    }

    /// The same file, grown: only the bytes past the old size are new.
    func isAppend(to older: FileSignature) -> Bool {
        inode == older.inode && size > older.size
    }
}

/// A directory's entries, or why there are none.
enum DirectoryListing: Sendable, Equatable {
    struct Entry: Sendable, Equatable {
        var name: String
        var isDirectory: Bool
    }

    case entries([Entry])
    /// The directory doesn't exist.
    case missing
    /// It exists but can't be listed (permissions, not a directory).
    case unreadable
}

/// Every file-system call CodexKit makes goes through here: directory listings, `stat`, and read-only opens of
/// rollouts and the two side files. Lock files are listed and stat'ed, never opened (1.1 §3.1). The counters let
/// tests check the poll budget (1.1 §3.3, §11.1).
///
/// Not thread-safe, like `CodexReader`, which owns it.
final class CodexFileAccess: @unchecked Sendable {
    /// Directories listed.
    private(set) var listings = 0
    /// Files opened for reading.
    private(set) var opens = 0
    /// Files stat'ed.
    private(set) var stats = 0

    func resetCounters() {
        listings = 0
        opens = 0
        stats = 0
    }

    func list(_ url: URL) -> DirectoryListing {
        listings += 1
        guard let directory = opendir(url.path) else {
            return errno == ENOENT ? .missing : .unreadable
        }
        defer { closedir(directory) }
        var entries: [DirectoryListing.Entry] = []
        while let entry = readdir(directory) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                String(decoding: raw.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
            }
            if name == "." || name == ".." { continue }
            let type = entry.pointee.d_type
            // DT_UNKNOWN (some file systems): treat as a possible directory; listing a file just fails.
            entries.append(.init(name: name, isDirectory: type == DT_DIR || type == DT_UNKNOWN))
        }
        return .entries(entries)
    }

    /// Follows symlinks. Nil when the path doesn't exist or can't be examined.
    func signature(of url: URL) -> FileSignature? {
        stats += 1
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return FileSignature(info)
    }

    /// Opens a regular file read-only and hands `body` the descriptor and its signature; nil when it can't be
    /// opened or isn't a regular file.
    func withOpenFile<T>(_ url: URL, _ body: (Int32, FileSignature) -> T?) -> T? {
        opens += 1
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return nil }
        let signature = FileSignature(info)
        guard signature.isRegularFile else { return nil }
        return body(descriptor, signature)
    }

    /// Up to `count` bytes from the start of the open file.
    static func readPrefix(_ descriptor: Int32, count: Int) -> [UInt8]? {
        guard count > 0 else { return [] }
        var failed = false
        let bytes = [UInt8](unsafeUninitializedCapacity: count) { buffer, initializedCount in
            guard let base = buffer.baseAddress else { return }
            var filled = 0
            while filled < count {
                let n = pread(descriptor, base + filled, count - filled, Int64(filled))
                if n > 0 {
                    filled += n
                } else if n < 0, errno == EINTR {
                    continue
                } else {
                    failed = n < 0
                    break
                }
            }
            initializedCount = filled
        }
        return failed ? nil : bytes
    }
}
