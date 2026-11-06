import Foundation

enum BoundedFileRead: Equatable {
    case file(Data, modified: Date?)
    /// Missing, not a regular file (directory, FIFO, …), or not readable.
    case unreadable
    case tooLarge
}

/// Reads a regular file (following symlinks) of at most `limit` bytes. Never opens special files, so a FIFO
/// can't block the poller, and never loads more than `limit + 1` bytes.
///
/// Uses `FileManager` attributes rather than `URL.resourceValues`, which caches per URL and is only flushed
/// on a run loop turn, so a long-lived reader polled from a background task would see a frozen mtime.
func readRegularFile(at url: URL, limit: Int) -> BoundedFileRead {
    let path = url.resolvingSymlinksInPath().path
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
          attributes[.type] as? FileAttributeType == .typeRegular,
          let handle = FileHandle(forReadingAtPath: path)
    else { return .unreadable }
    defer { try? handle.close() }
    do {
        // `read(upToCount:)` returns nil at end of file, i.e. for an empty file.
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        return data.count > limit ? .tooLarge : .file(data, modified: attributes[.modificationDate] as? Date)
    } catch {
        return .unreadable
    }
}
