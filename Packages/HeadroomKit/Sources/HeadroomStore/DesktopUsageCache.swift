import Foundation
import UsageKit

/// The desktop app's usage history (spec §2.1), read again only when the file's stamp changes.
///
/// An unrecognized file may have been caught mid-write, so the last good samples are kept for
/// `unrecognizedGrace` after the first failed read before the issue is reported and the samples dropped. With no
/// good samples to keep there is nothing to protect, and the issue is reported at once. A missing file is not an
/// issue (the desktop app may not be installed): no samples, no issue.
struct DesktopUsageCache {
    static let unrecognizedGrace: TimeInterval = 5 * 60

    struct Result: Equatable {
        var samples: [DesktopUsageSample]
        /// Report `DataIssue.desktopUsageUnrecognized`.
        var unrecognized: Bool
    }

    let reader: DesktopUsageReader
    private var stamp: FileStamp?
    /// The samples of the newest successful read.
    private var lastGood: [DesktopUsageSample] = []
    /// When a read first failed as unrecognized, since the last successful one.
    private var unrecognizedSince: Date?
    /// Number of times the file was read (for tests).
    private(set) var reads = 0

    init(fileURL: URL) {
        reader = DesktopUsageReader(fileURL: fileURL)
    }

    mutating func samples(now: Date) -> Result {
        guard let current = FileStamp.of(reader.fileURL) else {
            stamp = nil
            lastGood = []
            unrecognizedSince = nil
            return Result(samples: [], unrecognized: false)
        }
        if current != stamp {
            stamp = current
            read(now: now)
        }
        guard let since = unrecognizedSince else {
            return Result(samples: lastGood, unrecognized: false)
        }
        if !lastGood.isEmpty, now.timeIntervalSince(since) < Self.unrecognizedGrace {
            return Result(samples: lastGood, unrecognized: false)
        }
        lastGood = []
        return Result(samples: [], unrecognized: true)
    }

    private mutating func read(now: Date) {
        reads += 1
        do {
            lastGood = try reader.readSamples()
            unrecognizedSince = nil
        } catch DesktopUsageError.unrecognizedFormat {
            unrecognizedSince = unrecognizedSince ?? now
        } catch {
            // `fileMissing`: gone since it was stamped, or not a readable regular file. Not an issue.
            lastGood = []
            unrecognizedSince = nil
        }
    }
}
