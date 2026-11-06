import ContextKit
import Darwin
import Foundation
import Testing

/// ContextKit's generic tail reader (1.1 §3.3), tested here with the Codex stream that owns it.
@Suite struct JSONLTailReaderTests {
    /// Writes `text` to a fresh file, runs `body` with it open, and removes it.
    private func withFile<T>(_ text: String, _ body: (Int32, URL) throws -> T) throws -> T {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tail-\(UUID().uuidString).jsonl")
        try Data(text.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let descriptor = open(url.path, O_RDONLY)
        defer { close(descriptor) }
        return try body(descriptor, url)
    }

    private func size(_ descriptor: Int32) -> Int64 {
        var info = stat()
        fstat(descriptor, &info)
        return Int64(info.st_size)
    }

    private func lines(
        _ reader: JSONLTailReader, _ descriptor: Int32, from start: Int64 = 0, stopAt: String? = nil
    ) -> ([String], JSONLTailReader.Scan) {
        var seen: [String] = []
        let scan = reader.scan(descriptor: descriptor, from: start, size: size(descriptor)) { line in
            let text = String(decoding: line.bytes, as: UTF8.self)
            seen.append(line.isTerminated ? text : text + "…")
            return text == stopAt ? .stop : .next
        }
        return (seen, scan)
    }

    @Test func visitsNewestFirstDownToTheStart() throws {
        try withFile("a\nbb\nccc\n") { descriptor, _ in
            let (seen, scan) = lines(JSONLTailReader(), descriptor)
            #expect(seen == ["ccc", "bb", "a"])
            #expect(scan.reachedStart)
            #expect(!scan.stopped)
            #expect(scan.resumeOffset == 9)
            #expect(scan.bytesRead == 9)
        }
    }

    @Test func stopsWhenAsked() throws {
        try withFile("a\nbb\nccc\n") { descriptor, _ in
            let (seen, scan) = lines(JSONLTailReader(), descriptor, stopAt: "bb")
            #expect(seen == ["ccc", "bb"])
            #expect(scan.stopped)
            #expect(!scan.reachedStart)
        }
    }

    @Test func growsTheWindowAndNeverVisitsACutLine() throws {
        // 10-byte lines; windows 16, 64 (capped at 32): the cut line at the largest window's start is skipped.
        let text = (0..<10).map { String(format: "line-%04d", $0) }.joined(separator: "\n") + "\n"
        try withFile(text) { descriptor, _ in
            let reader = JSONLTailReader(initialWindow: 16, maxWindow: 32)
            let (seen, scan) = lines(reader, descriptor)
            #expect(seen == ["line-0009", "line-0008", "line-0007"])
            #expect(!scan.reachedStart)
            // Never more than the largest window plus one byte.
            #expect(scan.bytesRead <= 33)
        }
    }

    @Test func skipsLinesOverTheLengthLimit() throws {
        let long = String(repeating: "x", count: 100)
        try withFile("old\n\(long)\nnew\n") { descriptor, _ in
            let (seen, _) = lines(JSONLTailReader(maxLineLength: 50), descriptor)
            #expect(seen == ["new", "old"])
        }
    }

    @Test func anUnterminatedLastLineIsVisitedButNotResumedPast() throws {
        try withFile("a\nbb\n{\"partial\":") { descriptor, url in
            let reader = JSONLTailReader()
            let (seen, scan) = lines(reader, descriptor)
            #expect(seen == [#"{"partial":…"#, "bb", "a"])
            #expect(scan.resumeOffset == 5)

            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("1}\ndd\n".utf8))
            try handle.close()
            let (appended, next) = lines(reader, descriptor, from: scan.resumeOffset)
            #expect(appended == ["dd", #"{"partial":1}"#])
            #expect(next.reachedStart)
            #expect(next.bytesRead == 17)
            #expect(next.resumeOffset == size(descriptor))
        }
    }

    @Test func appendedBytesOnlyAreRead() throws {
        try withFile("one\ntwo\n") { descriptor, url in
            let reader = JSONLTailReader()
            let (_, first) = lines(reader, descriptor)
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("three\nfour\n".utf8))
            try handle.close()
            let (seen, scan) = lines(reader, descriptor, from: first.resumeOffset)
            #expect(seen == ["four", "three"])
            #expect(scan.bytesRead == 11)
            // Nothing new: nothing read.
            let (none, idle) = lines(reader, descriptor, from: scan.resumeOffset)
            #expect(none.isEmpty)
            #expect(idle.bytesRead == 0)
        }
    }

    @Test func appendedReadsLongerThanTheWindowReadOnlyTheirTail() throws {
        try withFile("start\n") { descriptor, url in
            let reader = JSONLTailReader(initialWindow: 8, maxWindow: 16)
            let (_, first) = lines(reader, descriptor)
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((0..<20).map { "n\($0)" }.joined(separator: "\n").appending("\n").utf8))
            try handle.close()
            let (seen, scan) = lines(reader, descriptor, from: first.resumeOffset)
            #expect(seen.first == "n19")
            #expect(!seen.contains("start"))
            #expect(scan.bytesRead <= 17 + 8)
        }
    }

    @Test func lineHelpers() throws {
        try withFile(#"{"type":"token_count"}"# + "\n") { descriptor, _ in
            var matched = false
            _ = JSONLTailReader().scan(descriptor: descriptor, size: size(descriptor)) { line in
                matched = line.contains(Array(#""token_count""#.utf8))
                    && !line.contains(Array("task_started".utf8))
                    && line.containsAny([Array("nope".utf8), Array("type".utf8)])
                    && line.data.count == 22
                    && line.offset == 0
                return .stop
            }
            #expect(matched)
        }
    }

    @Test func anEmptyRangeReadsNothing() throws {
        try withFile("") { descriptor, _ in
            let (seen, scan) = lines(JSONLTailReader(), descriptor)
            #expect(seen.isEmpty)
            #expect(scan.bytesRead == 0)
            #expect(scan.reachedStart)
        }
    }
}
