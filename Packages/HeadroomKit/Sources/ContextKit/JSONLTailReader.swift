import Darwin
import Foundation

/// Reads a JSON Lines file backwards from its end, newest line first, in growing windows: the last 256 KB, then ×4
/// up to 8 MB, until the visitor has what it needs (1.1 §3.3). Only the last `maxWindow` bytes (plus one) of the
/// range are ever read, each at most once: a growth step reads just the part of the window not yet read, and the
/// line cut at the previous window's start is carried over (or dropped, once it is known to be too long).
///
/// A scan can start at `from`, a line start such as the `resumeOffset` of an earlier scan of the same file: on an
/// unchanged file that only grew, that reads just the appended bytes.
///
/// Generic: it knows nothing about the lines' JSON. `TranscriptTailScanner` keeps its own specialised loop.
public struct JSONLTailReader: Sendable {
    public static let defaultInitialWindow = 256 * 1_024
    public static let defaultMaxWindow = 8 * 1_024 * 1_024
    /// Lines longer than this are skipped unread (1.1 §3.3: 4 MB).
    public static let defaultMaxLineLength = 4 * 1_024 * 1_024
    public static let growthFactor = 4

    public var initialWindow: Int
    public var maxWindow: Int
    public var maxLineLength: Int

    public init(
        initialWindow: Int = Self.defaultInitialWindow,
        maxWindow: Int = Self.defaultMaxWindow,
        maxLineLength: Int = Self.defaultMaxLineLength
    ) {
        self.initialWindow = initialWindow
        self.maxWindow = maxWindow
        self.maxLineLength = maxLineLength
    }

    /// What the visitor wants after a line.
    public enum Decision: Sendable {
        /// Visit the next older line, growing the window when needed.
        case next
        /// Done: read nothing more.
        case stop
    }

    /// One line of the file, without its newline. The bytes share the scan's buffer: copy what you keep.
    public struct Line {
        /// The line's bytes.
        public let bytes: ArraySlice<UInt8>
        /// The file offset of the line's first byte.
        public let offset: Int64
        /// False for the file's last line when no newline ends it yet: it may still be mid-write.
        public let isTerminated: Bool

        /// Whether `needle` occurs anywhere in the line: a cheap check before decoding.
        public func contains(_ needle: [UInt8]) -> Bool {
            guard !needle.isEmpty, needle.count <= bytes.count else { return needle.isEmpty }
            return bytes.withUnsafeBytes { line in
                needle.withUnsafeBytes { memmem(line.baseAddress, line.count, $0.baseAddress, $0.count) != nil }
            }
        }

        /// Whether any of `needles` occurs in the line.
        public func containsAny(_ needles: [[UInt8]]) -> Bool {
            needles.contains { contains($0) }
        }

        /// The line as `Data`, for a decoder.
        public var data: Data { Data(bytes) }
    }

    /// What a scan did.
    public struct Scan: Sendable, Equatable {
        /// Bytes read from the file.
        public var bytesRead: Int64
        /// Where a later scan of the appended bytes starts: just past the newest newline in the range, or the
        /// range's start when none was seen. Lines after it (an unterminated last line) are read again then.
        public var resumeOffset: Int64
        /// Every line down to the range's start was visited (or skipped as too long).
        public var reachedStart: Bool
        /// The visitor returned `.stop`.
        public var stopped: Bool

        public init(bytesRead: Int64, resumeOffset: Int64, reachedStart: Bool, stopped: Bool) {
            self.bytesRead = bytesRead
            self.resumeOffset = resumeOffset
            self.reachedStart = reachedStart
            self.stopped = stopped
        }
    }

    /// Visits the lines of the open regular file `descriptor` in `from..<size`, newest first, until `visit` returns
    /// `.stop`, the range's start is reached or the window reaches `maxWindow`. `from` must be 0 or a line start.
    /// Lines longer than `maxLineLength`, and the line cut off at the start of the largest window, are skipped.
    /// Each byte is read at most once: at most `maxWindow` + 1 bytes in all.
    public func scan(
        descriptor: Int32,
        from start: Int64 = 0,
        size: Int64,
        visit: (Line) -> Decision
    ) -> Scan {
        let start = max(0, start)
        var scan = Scan(bytesRead: 0, resumeOffset: min(start, max(0, size)), reachedStart: size <= start, stopped: false)
        guard size > start else { return scan }
        let limit = Int64(max(1, maxWindow))
        var window = min(Int64(max(1, initialWindow)), limit)
        // Bytes from `readEnd` on are read; `carry` holds the ones not visited yet: the line cut at `readEnd` (with
        // its newline, if it has one). When that line is already known to be too long, its bytes aren't kept and
        // `skipCutLine` skips its first part in the next chunk.
        var readEnd = size
        var carry: [UInt8] = []
        var skipCutLine = false
        var sawNewline = false
        while true {
            let windowStart = max(start, size - window)
            // One extra byte before the window tells whether its first line starts exactly at the window start
            // (complete) or earlier (a fragment that must not be visited yet). At `start` there is no fragment.
            let readStart = windowStart > start ? windowStart - 1 : start
            guard readStart < readEnd, let fresh = Self.read(descriptor, offset: readStart, count: Int(readEnd - readStart))
            else { return scan }
            scan.bytesRead += Int64(fresh.count)
            let chunk = carry.isEmpty ? fresh : fresh + carry
            let newlines = Self.newlineOffsets(chunk)
            if !sawNewline, let last = newlines.last {
                scan.resumeOffset = readStart + Int64(last) + 1
                sawNewline = true
            }
            let startsMidLine = readStart > start
            let oldest = startsMidLine ? 1 : 0
            for index in stride(from: newlines.count, through: oldest, by: -1) {
                let isCutLine = index == newlines.count
                if isCutLine, skipCutLine { continue }
                let lineStart = index == 0 ? 0 : newlines[index - 1] + 1
                let lineEnd = isCutLine ? chunk.count : newlines[index]
                guard lineEnd > lineStart, lineEnd - lineStart <= maxLineLength else { continue }
                let line = Line(bytes: chunk[lineStart..<lineEnd], offset: readStart + Int64(lineStart), isTerminated: !isCutLine)
                if visit(line) == .stop {
                    scan.stopped = true
                    return scan
                }
            }
            if !startsMidLine {
                scan.reachedStart = true
                return scan
            }
            if window >= limit { return scan }
            // The fragment before the first newline (all of the chunk without one) is completed by the next,
            // larger window; carry it instead of reading it again.
            let fragmentEnd = newlines.first.map { $0 + 1 } ?? chunk.count
            let fragmentLength = (newlines.first ?? chunk.count) + (newlines.isEmpty && skipCutLine ? maxLineLength + 1 : 0)
            if fragmentLength > maxLineLength {
                carry = []
                skipCutLine = true
            } else {
                carry = Array(chunk[0..<fragmentEnd])
                skipCutLine = false
            }
            readEnd = readStart
            window = min(window * Int64(Self.growthFactor), limit)
        }
    }

    private static func newlineOffsets(_ chunk: [UInt8]) -> [Int] {
        chunk.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return [] }
            var offsets: [Int] = []
            var position = 0
            while position < raw.count, let hit = memchr(base + position, 0x0A, raw.count - position) {
                let offset = base.distance(to: UnsafeRawPointer(hit))
                offsets.append(offset)
                position = offset + 1
            }
            return offsets
        }
    }

    /// Up to `count` bytes at `offset`; fewer if the file shrank meanwhile. Nil on a read error.
    private static func read(_ descriptor: Int32, offset: Int64, count: Int) -> [UInt8]? {
        guard count > 0 else { return [] }
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
