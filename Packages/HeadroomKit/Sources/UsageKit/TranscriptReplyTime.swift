import Darwin
import Foundation

/// When a Claude Code session last got an API reply: the `timestamp` of the newest assistant entry in its
/// transcript (layout in spec §2.3).
///
/// Rate limits change only with API replies, and Claude Code re-runs the status line from its cached values without
/// one (at the earliest `resets_at`, at prompt-cache expiry, on UI changes), so this dates the numbers a status
/// line payload carries. Subagent (`isSidechain`) replies count: they refresh the same process's rate limits.
/// `<synthetic>` entries are made up locally and don't.
///
/// Reads only the tail, like ContextKit: the last 64 KB, then ×4 up to 8 MB, until a reply is found.
enum TranscriptReplyTime {
    static let initialWindow = 64 * 1_024
    static let maxWindow = 8 * 1_024 * 1_024
    static let growthFactor = 4

    /// Nil when `path` isn't absolute, isn't a readable regular file, or has no reply in its last `maxWindow` bytes.
    static func newestReply(
        inTranscriptAt path: String, initialWindow: Int = initialWindow, maxWindow: Int = maxWindow
    ) -> Date? {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { return nil }
        // O_NONBLOCK: a FIFO at that path must not wait for a writer.
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG, status.st_size > 0 else {
            return nil
        }
        let size = Int64(status.st_size)
        let limit = Int64(max(1, maxWindow))
        var window = min(Int64(max(1, initialWindow)), limit)
        while true {
            let windowStart = max(0, size - window)
            // One byte before the window tells whether its first line starts exactly at the window start
            // (complete) or earlier (a fragment that must not be parsed).
            let readStart = max(0, windowStart - 1)
            guard let chunk = read(descriptor, offset: readStart, count: Int(size - readStart)) else { return nil }
            if let reply = newestReply(in: chunk, startsMidLine: readStart > 0) { return reply }
            if readStart == 0 || window >= limit { return nil }
            window = min(window * Int64(growthFactor), limit)
        }
    }

    /// The newest reply among the complete lines of `chunk`, scanning from the last line back.
    static func newestReply(in chunk: Data, startsMidLine: Bool) -> Date? {
        var lines = chunk.split(separator: newline, omittingEmptySubsequences: false)
        if startsMidLine, !lines.isEmpty { lines.removeFirst() }
        let decoder = JSONDecoder()
        for line in lines.reversed() where line.range(of: assistantValue) != nil {
            if let entry = try? decoder.decode(Entry.self, from: line), let reply = entry.replyTime {
                return reply
            }
        }
        return nil
    }

    private static let newline = UInt8(ascii: "\n")
    /// Every reply line contains these bytes; other lines are not decoded.
    private static let assistantValue = Data(#""assistant""#.utf8)

    private struct Entry: Decodable {
        var type: String?
        var timestamp: String?
        var message: Message?

        struct Message: Decodable {
            var model: String?
        }

        var replyTime: Date? {
            guard type == "assistant", let message, message.model != "<synthetic>", let timestamp else { return nil }
            return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(timestamp))
                ?? (try? Date.ISO8601FormatStyle().parse(timestamp))
        }
    }

    /// Up to `count` bytes at `offset`; fewer if the file shrank meanwhile. Nil on a read error.
    private static func read(_ descriptor: Int32, offset: Int64, count: Int) -> Data? {
        var data = Data(count: count)
        var filled = 0
        let failed = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            while filled < count {
                let n = pread(descriptor, base + filled, count - filled, offset + Int64(filled))
                if n > 0 {
                    filled += n
                } else if n < 0, errno == EINTR {
                    continue
                } else {
                    return n < 0
                }
            }
            return false
        }
        guard !failed else { return nil }
        data.count = filled
        return data
    }
}
