import Foundation
import HeadroomModel
import UsageKit

/// The terminal limits (spec §2.4), read again only when `statusline-latest.json` changes stamp or the transcript
/// its payload names does: the readings are dated by that transcript's newest reply (UsageKit's
/// `TerminalLimitsReader`), which can reach the transcript after the status line wrote the file.
struct TerminalLimitsCache {
    private var fileStamp: FileStamp?
    /// The transcript the cached reading was dated by, and its stamp just before it was read.
    private var transcriptPath: String?
    private var transcriptStamp: FileStamp?
    private var cached: PlanUsage?
    private var hasCached = false
    /// Number of times the file was read (for tests).
    private(set) var reads = 0

    /// Nil when nothing exists at the reader's file (the cached reading is dropped), or it holds no limits.
    ///
    /// Each stamp is taken before the read it stands for: should a file change in between, the next call sees a
    /// new stamp and reads again, so the cache never keeps content older than the files.
    mutating func value(from reader: TerminalLimitsReader) -> PlanUsage? {
        guard let current = FileStamp.of(reader.fileURL) else {
            hasCached = false
            cached = nil
            return nil
        }
        if hasCached, current == fileStamp, transcriptPath.flatMap(FileStamp.of(path:)) == transcriptStamp {
            return cached
        }
        var path: String?
        var stamp: FileStamp?
        let fresh = reader.read { transcript in
            path = transcript
            stamp = FileStamp.of(path: transcript)
        }
        reads += 1
        fileStamp = current
        transcriptPath = path
        transcriptStamp = stamp
        cached = fresh
        hasCached = true
        return fresh
    }
}

/// A value parsed from the files of one directory, parsed again only when a matching file is added, removed
/// or changes stamp. A directory that can't be listed is never cached.
struct DirectoryCache<Value> {
    private var stamp: DirectoryStamp?
    private var cached: Value?
    /// Number of times `read` ran (for tests).
    private(set) var reads = 0

    /// A throwing `read` leaves nothing cached, so the next call tries again.
    mutating func value(
        of directory: URL,
        including include: (String) -> Bool,
        read: () throws -> Value
    ) rethrows -> Value {
        let current = DirectoryStamp.of(directory: directory, including: include)
        if let cached, let current, current == stamp {
            return cached
        }
        stamp = nil
        cached = nil
        reads += 1
        let fresh = try read()
        stamp = current
        cached = fresh
        return fresh
    }
}
