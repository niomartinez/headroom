import Foundation
import Testing
@testable import ContextKit

/// Checks the growing tail window against a plain whole-file reference on many random transcripts
/// with tiny windows, so every boundary case (a line starting exactly at the window start, a cut-off
/// first line that is itself valid JSON, a missing final newline, CRLF, blank lines) comes up often.
@Suite("Tail window vs. whole-file reference (spec §2.3)")
struct TranscriptWindowingDifferentialTests {
    /// SplitMix64, so failures reproduce.
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// The last usable line of the whole file, if it starts within the last `maxWindow` bytes.
    /// The reader also reads the byte before its largest window, so the file's first line counts
    /// too when the file is only one byte longer than the window: that line is complete.
    static func reference(_ bytes: [UInt8], maxWindow: Int) -> TranscriptUsage? {
        var lines: [Range<Int>] = []
        var start = 0
        for (offset, byte) in bytes.enumerated() where byte == 0x0A {
            lines.append(start..<offset)
            start = offset + 1
        }
        if start < bytes.count { lines.append(start..<bytes.count) }
        let decoder = JSONDecoder()
        for line in lines.reversed() where !line.isEmpty {
            if let usage = (try? decoder.decode(TranscriptEntry.self, from: Data(bytes[line])))?.usage {
                let reachable = line.lowerBound >= bytes.count - maxWindow
                    || (line.lowerBound == 0 && bytes.count <= maxWindow + 1)
                return reachable ? usage : nil
            }
        }
        return nil
    }

    static func randomTranscript(_ id: Int, using rng: inout SeededGenerator) -> String {
        var text = ""
        for index in 0..<Int.random(in: 0...12, using: &rng) {
            switch Int.random(in: 0..<7, using: &rng) {
            case 0, 1:
                let padding = String(repeating: "t", count: Int.random(in: 0...200, using: &rng))
                text += Fixture.assistant(model: "claude-\(id)-\(index)", text: padding)
            case 2:
                text += Fixture.filler(bytes: Int.random(in: Fixture.fillerOverhead...400, using: &rng))
            case 3:
                text += Fixture.assistant(model: "claude-side", sidechain: true)
            case 4:
                // A malformed line whose tail is a valid, usable entry: it must never count, even
                // when a window starts right before that tail.
                text += "#" + String(repeating: " ", count: Int.random(in: 0...50, using: &rng))
                    + Fixture.assistant(model: "claude-fragment-\(id)-\(index)")
            case 5:
                text += "\n"
            default:
                text += String(repeating: "q", count: Int.random(in: 1...300, using: &rng)) + "\n"
            }
        }
        if Bool.random(using: &rng) { text = text.replacingOccurrences(of: "\n", with: "\r\n") }
        if Bool.random(using: &rng), !text.isEmpty { text.removeLast() }
        return text
    }

    /// Half the time a window edge falls exactly on a line start (or one byte either side of it),
    /// the case the extra byte read before each window exists for.
    static func randomWindows(for bytes: [UInt8], using rng: inout SeededGenerator) -> (initial: Int, max: Int) {
        let lineStarts = [0] + bytes.indices.filter { bytes[$0] == 0x0A }.map { $0 + 1 }.filter { $0 < bytes.count }
        func aligned() -> Int {
            let start = lineStarts.randomElement(using: &rng) ?? 0
            return max(1, bytes.count - start + Int.random(in: -1...1, using: &rng))
        }
        let maxWindow = Bool.random(using: &rng) ? aligned() : Int.random(in: 1...3_000, using: &rng)
        let initial = Bool.random(using: &rng) ? min(aligned(), maxWindow) : Int.random(in: 1...maxWindow, using: &rng)
        return (initial, maxWindow)
    }

    @Test func matchesTheWholeFileReference() throws {
        var rng = SeededGenerator(state: 0x4845_4144_524F_4F4D)
        try withTempDirectory { tmp in
            let url = tmp.appendingPathComponent("session.jsonl")
            var mismatches = 0
            for id in 0..<400 {
                let text = Self.randomTranscript(id, using: &rng)
                let (initial, maxWindow) = Self.randomWindows(for: Array(text.utf8), using: &rng)
                try url.write(text)
                let got = TranscriptContextReader(initialWindow: initial, maxWindow: maxWindow).latestUsage(at: url)
                let want = Self.reference(Array(text.utf8), maxWindow: maxWindow)
                if got != want {
                    mismatches += 1
                    if mismatches <= 3 {
                        Issue.record("case \(id), window \(initial)...\(maxWindow), \(text.utf8.count) bytes: got \(got?.model ?? "nil"), want \(want?.model ?? "nil")")
                    }
                }
            }
            #expect(mismatches == 0)
        }
    }
}
