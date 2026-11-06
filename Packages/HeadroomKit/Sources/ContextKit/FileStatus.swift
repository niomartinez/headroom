import Darwin

/// Size and modification time: what the transcript cache is keyed on (spec §2.3).
struct FileSignature: Sendable, Equatable {
    var size: Int64
    var modifiedSeconds: Int
    var modifiedNanoseconds: Int

    func isModified(after other: FileSignature) -> Bool {
        (modifiedSeconds, modifiedNanoseconds) > (other.modifiedSeconds, other.modifiedNanoseconds)
    }
}

/// The parts of `stat(2)` ContextKit needs.
struct FileStatus: Sendable {
    var isRegularFile: Bool
    var signature: FileSignature

    init(_ info: stat) {
        isRegularFile = (info.st_mode & S_IFMT) == S_IFREG
        signature = FileSignature(
            size: Int64(info.st_size),
            modifiedSeconds: Int(info.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int(info.st_mtimespec.tv_nsec)
        )
    }

    /// Follows symlinks. Nil when the path does not exist or cannot be examined.
    static func of(path: String) -> FileStatus? {
        guard !path.isEmpty, !path.utf8.contains(0) else { return nil }
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return FileStatus(info)
    }

    static func of(descriptor: Int32) -> FileStatus? {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return nil }
        return FileStatus(info)
    }
}
