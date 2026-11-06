import Foundation
import Testing
@testable import ContextKit

/// Transcripts can be 80 MB+; only the tail may be read (spec §2.3). A read should take well under
/// 100 ms. Each case is timed over several uncached reads and judged on their median, with a ceiling
/// for any single read, so a busy machine (parallel tests, other builds) doesn't flake while a gross
/// slowdown still fails. The clock can't tell a tail read from a whole-file one (60 MB is read in tens
/// of milliseconds): how far back the reader looks is checked without it, in `TranscriptTailReadingTests`.
@Suite("Transcript tail reading performance", .serialized)
struct TranscriptPerformanceTests {
    static let medianBound: Duration = .milliseconds(250)
    static let ceiling: Duration = .seconds(2)
    static let runs = 5

    /// Writes `megabytes` MB of filler, then `tail`, to a fresh file, and reads it `runs` times, each
    /// with a new `TranscriptContextReader` (nothing cached). Returns the time each read took, the
    /// first read's result and the file size.
    static func measureReads(megabytes: Int, tail: String) throws -> ([Duration], TranscriptUsage?, Int) {
        try withTempDirectory { tmp in
            let url = tmp.appendingPathComponent("large.jsonl")
            #expect(FileManager.default.createFile(atPath: url.path, contents: nil))
            let handle = try FileHandle(forWritingTo: url)
            try Fixture.writeLargeFiller(megabytes: megabytes, to: handle)
            try handle.write(contentsOf: Data(tail.utf8))
            try handle.close()

            var first: TranscriptUsage?
            var times: [Duration] = []
            for run in 0..<runs {
                let reader = TranscriptContextReader()
                var usage: TranscriptUsage?
                times.append(ContinuousClock().measure { usage = reader.latestUsage(at: url) })
                if run == 0 { first = usage } else { #expect(usage == first) }
            }
            return (times, first, url.fileSize)
        }
    }

    /// The median read stays under `medianBound`, and every read under `ceiling`.
    static func checkTimes(_ times: [Duration], _ label: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let sorted = times.sorted()
        guard let slowest = sorted.last else {
            Issue.record("\(label): no reads", sourceLocation: sourceLocation)
            return
        }
        let median = sorted[sorted.count / 2]
        #expect(median < medianBound, "\(label): median \(median) of \(times)", sourceLocation: sourceLocation)
        #expect(slowest < ceiling, "\(label): slowest \(slowest) of \(times)", sourceLocation: sourceLocation)
    }

    @Test func sixtyMegabyteTranscriptIsReadFromTheTail() throws {
        let tail = Fixture.assistant(model: "claude-at-the-end") + Fixture.filler(bytes: 50_000)
        let (times, usage, size) = try Self.measureReads(megabytes: 60, tail: tail)
        #expect(size > 60 * 1_048_576)
        #expect(usage?.model == "claude-at-the-end")
        Self.checkTimes(times, "tail read")
    }

    /// Worst case: the usable line is almost 8 MB back behind sidechain assistant entries, which
    /// all pass the cheap pre-filter and must be decoded before being rejected.
    @Test func worstCaseEightMegabyteScanStaysFast() throws {
        let decoy = Fixture.assistant(model: "claude-side", sidechain: true, text: String(repeating: "z", count: 1_500))
        let decoys = String(repeating: decoy, count: (7 * 1_048_576) / decoy.utf8.count)
        let tail = Fixture.assistant(model: "claude-deep") + decoys
        let (times, usage, _) = try Self.measureReads(megabytes: 60, tail: tail)
        #expect(usage?.model == "claude-deep")
        Self.checkTimes(times, "worst-case read")
    }

    /// Worst case for the window evidence search (spec §2.3): the usable line of a model with no known
    /// window is found ~6 MB back, behind sidechain decoys, with megabytes of older main-thread replies of
    /// the same model before it in the same read. Only a bounded stretch of those may be decoded.
    @Test func olderReplySearchStaysFast() throws {
        let decoy = Fixture.assistant(model: "claude-side", sidechain: true, text: String(repeating: "z", count: 1_500))
        let older = Fixture.assistant(model: "claude-unknown", cacheRead: 150_000, text: String(repeating: "o", count: 1_500))
        let tail = String(repeating: older, count: (4 * 1_048_576) / older.utf8.count)
            + Fixture.assistant(model: "claude-unknown")
            + String(repeating: decoy, count: (6 * 1_048_576) / decoy.utf8.count)
        let (times, usage, _) = try Self.measureReads(megabytes: 60, tail: tail)
        #expect(usage?.model == "claude-unknown")
        Self.checkTimes(times, "evidence search read")
    }
}
