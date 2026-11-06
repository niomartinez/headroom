import Darwin

/// Reads a transcript backwards from its end in growing windows: the last 256 KB, then ×4 up to
/// 8 MB, until a usable line is found (spec §2.3). Transcripts can be 80 MB+; only the last
/// `maxWindow` bytes (plus one) are ever read, and each growth step reads just the part of the
/// window not yet scanned plus the cut-off line it completes.
struct TranscriptTailScanner: Sendable {
    static let initialWindow = 256 * 1_024
    static let maxWindow = 8 * 1_024 * 1_024
    static let growthFactor = 4

    var initialWindow = Self.initialWindow
    var maxWindow = Self.maxWindow

    struct Finding {
        /// The newest usable entry.
        var usage: TranscriptUsage
        /// Older usable entries above the standard window, from the lines already read (see
        /// `TranscriptLineScanner.Result.olderAboveStandardWindow`). Only looked for when `searchOlder(usage)` is true.
        var olderAboveStandardWindow: [TranscriptUsage]
    }

    /// The newest usable entry in the open regular file `descriptor`, which is `size` bytes long.
    ///
    /// When `searchOlder(usage)` is true, older lines already read are searched as well, back to
    /// `TranscriptLineScanner.olderSearchLimit` bytes before it; nothing more is read for them.
    func newestUsage(
        descriptor: Int32,
        size: Int64,
        searchOlder: (TranscriptUsage) -> Bool = { _ in false }
    ) -> Finding? {
        guard size > 0 else { return nil }
        let limit = Int64(maxWindow)
        var window = Int64(max(1, initialWindow))
        // Everything from `end` on has been scanned already; `end` is always EOF or just past a newline.
        var end = size
        while true {
            let windowStart = max(0, size - window)
            // One extra byte before the window tells whether its first line starts exactly at the
            // window start (complete) or earlier (a fragment that must not be parsed).
            let readStart = max(0, windowStart - 1)
            guard readStart < end, let chunk = Self.read(descriptor, offset: readStart, count: Int(end - readStart)) else {
                return nil
            }
            let result = TranscriptLineScanner.scan(chunk, startsMidLine: readStart > 0, searchOlder: searchOlder)
            if let usage = result.usage {
                return Finding(usage: usage, olderAboveStandardWindow: result.olderAboveStandardWindow)
            }
            if readStart == 0 || window >= limit { return nil }
            // The fragment before the first newline is completed by the next, larger window.
            if let firstNewline = result.firstNewline {
                end = readStart + Int64(firstNewline) + 1
            }
            window = min(window * Int64(Self.growthFactor), limit)
        }
    }

    /// Up to `count` bytes at `offset`; fewer if the file shrank meanwhile. Nil on a read error.
    private static func read(_ descriptor: Int32, offset: Int64, count: Int) -> [UInt8]? {
        var failed = false
        let bytes = [UInt8](unsafeUninitializedCapacity: count) { buffer, initializedCount in
            guard let base = buffer.baseAddress else { return }
            var filled = 0
            while filled < count {
                let n = pread(descriptor, base + filled, count - filled, offset + Int64(filled))
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
