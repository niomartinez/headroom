import Darwin
import Foundation

/// Finds the newest usable entry among the lines of a chunk of transcript bytes (spec §2.3).
enum TranscriptLineScanner {
    struct Result {
        /// The newest usable entry among the complete lines of the chunk.
        var usage: TranscriptUsage?
        /// Offset of the first newline in the chunk.
        var firstNewline: Int?
        /// The usable entries older than `usage` that used more than the standard window (spec §2.3), newest
        /// first, among the complete lines of the chunk starting at most `olderSearchLimit` bytes before
        /// `usage`'s line. Only looked for when `searchOlder(usage)` is true.
        var olderAboveStandardWindow: [TranscriptUsage] = []
    }

    /// How far back before the newest usable entry older lines are searched: a bound on the decoding the
    /// search adds to a read, as the chunk can be megabytes long.
    static let olderSearchLimit = 256 * 1_024

    /// Scans the lines of `chunk` from last to first. When `startsMidLine`, the bytes before the first
    /// newline are the end of a line that began before the chunk and are not parsed.
    ///
    /// Once the newest usable entry is found, older lines are decoded too when `searchOlder` asks for it.
    static func scan(
        _ chunk: [UInt8],
        startsMidLine: Bool,
        olderSearchLimit: Int = Self.olderSearchLimit,
        searchOlder: (TranscriptUsage) -> Bool = { _ in false }
    ) -> Result {
        chunk.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, raw.count > 0 else { return Result() }
            let newlines = newlineOffsets(base, count: raw.count)
            let decoder = JSONDecoder()
            let oldest = startsMidLine ? 1 : 0
            // Line i runs from just after newline i-1 (or the chunk start) to newline i (or the chunk end).
            func line(_ index: Int) -> Range<Int> {
                let start = index == 0 ? 0 : newlines[index - 1] + 1
                let end = index < newlines.count ? newlines[index] : raw.count
                return start..<max(start, end)
            }
            func usableEntry(in line: Range<Int>) -> TranscriptUsage? {
                line.isEmpty ? nil : Self.usage(inLine: base + line.lowerBound, count: line.count, decoder: decoder)
            }
            for index in stride(from: newlines.count, through: oldest, by: -1) {
                let newestLine = line(index)
                guard let newest = usableEntry(in: newestLine) else { continue }
                var result = Result(usage: newest, firstNewline: newlines.first)
                if searchOlder(newest) {
                    for olderIndex in stride(from: index - 1, through: oldest, by: -1) {
                        let olderLine = line(olderIndex)
                        if olderLine.lowerBound < newestLine.lowerBound - olderSearchLimit { break }
                        if let older = usableEntry(in: olderLine), older.usedTokens > ContextWindowResolver.standardWindow {
                            result.olderAboveStandardWindow.append(older)
                        }
                    }
                }
                return result
            }
            return Result(usage: nil, firstNewline: newlines.first)
        }
    }

    private static func newlineOffsets(_ base: UnsafeRawPointer, count: Int) -> [Int] {
        var offsets: [Int] = []
        var position = 0
        while position < count, let hit = memchr(base + position, 0x0A, count - position) {
            let offset = base.distance(to: UnsafeRawPointer(hit))
            offsets.append(offset)
            position = offset + 1
        }
        return offsets
    }

    private static let assistantValue = Array(#""assistant""#.utf8)
    private static let usageKey = Array(#""usage""#.utf8)

    /// Only lines containing both `"assistant"` and `"usage"` are decoded. Every usable entry
    /// contains both byte sequences, so this cheap check never rejects one.
    private static func usage(inLine line: UnsafeRawPointer, count: Int, decoder: JSONDecoder) -> TranscriptUsage? {
        guard contains(usageKey, in: line, count: count), contains(assistantValue, in: line, count: count) else {
            return nil
        }
        let data = Data(bytes: line, count: count)
        return (try? decoder.decode(TranscriptEntry.self, from: data))?.usage
    }

    private static func contains(_ needle: [UInt8], in haystack: UnsafeRawPointer, count: Int) -> Bool {
        needle.withUnsafeBytes { memmem(haystack, count, $0.baseAddress, $0.count) != nil }
    }
}
