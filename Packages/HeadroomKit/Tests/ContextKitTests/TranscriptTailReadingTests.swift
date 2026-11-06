import Darwin
import Foundation
import Testing
@testable import ContextKit

@Suite("TranscriptContextReader tail reading (spec §2.3)")
struct TranscriptTailReadingTests {
    static func read(_ text: String, reader: TranscriptContextReader = TranscriptContextReader()) throws -> TranscriptUsage? {
        try withTempDirectory { tmp in
            let url = tmp.appendingPathComponent("session.jsonl")
            try url.write(text)
            return reader.latestUsage(at: url)
        }
    }

    // MARK: Picking the line

    @Test func returnsTheLastUsableAssistantLine() throws {
        let text = Fixture.user()
            + Fixture.assistant(model: "claude-old", input: 1, cacheCreation: 1, cacheRead: 1, output: 1)
            + Fixture.user()
            + Fixture.assistant(model: "claude-opus-5-5", input: 4, cacheCreation: 1_200, cacheRead: 134_000, output: 350)
            + Fixture.user(text: "trailing prompt")
        let usage = try #require(try Self.read(text))
        #expect(usage.usedTokens == 4 + 1_200 + 134_000 + 350)
        #expect(usage.model == "claude-opus-5-5")
        let timestamp = try #require(usage.timestamp)
        #expect(abs(timestamp.timeIntervalSince(Fixture.timestampDate)) < 0.001)
    }

    @Test func skipsSidechainSyntheticAndUsagelessEntries() throws {
        let text = Fixture.assistant(model: "claude-main", cacheRead: 5_000)
            + Fixture.assistant(model: "claude-side", sidechain: true)
            + Fixture.assistant(model: "<synthetic>", input: 0, cacheCreation: 0, cacheRead: 0, output: 0)
            + Fixture.assistant(usageJSON: nil, model: "claude-no-usage")
            + Fixture.assistant(usageJSON: "{}", model: "claude-empty-usage")
            + Fixture.assistant(usageJSON: "null", model: "claude-null-usage")
            + #"{"type":"attachment","usage":{"input_tokens":9},"message":{"model":"claude-attachment","usage":{"input_tokens":9}}}"# + "\n"
        let usage = try #require(try Self.read(text))
        #expect(usage.model == "claude-main")
        #expect(usage.usedTokens == 10 + 200 + 5_000 + 40)
    }

    @Test func missingSidechainFlagCountsAsMainThread() throws {
        let usage = try #require(try Self.read(Fixture.assistant(model: "claude-main", sidechain: nil)))
        #expect(usage.model == "claude-main")
    }

    @Test func missingTokenFieldsCountAsZero() throws {
        let usage = try #require(try Self.read(Fixture.assistant(usageJSON: #"{"input_tokens":7,"output_tokens":5}"#)))
        #expect(usage.usedTokens == 12)
    }

    @Test func missingModelIsAllowed() throws {
        let usage = try #require(try Self.read(Fixture.assistant(model: nil)))
        #expect(usage.model == nil)
        #expect(usage.usedTokens == 3_250)
    }

    @Test func timestampWithoutFractionalSecondsParses() throws {
        let usage = try #require(try Self.read(Fixture.assistant(timestamp: "2026-01-02T03:04:05Z")))
        #expect(usage.timestamp == Date(timeIntervalSince1970: 1_767_323_045))
    }

    @Test(arguments: [nil, "yesterday", "2026-13-45T99:00:00Z"] as [String?])
    func badOrMissingTimestampKeepsTheUsage(_ timestamp: String?) throws {
        let usage = try #require(try Self.read(Fixture.assistant(timestamp: timestamp)))
        #expect(usage.timestamp == nil)
        #expect(usage.usedTokens == 3_250)
    }

    @Test func skipsMalformedLines() throws {
        let text = Fixture.assistant(model: "claude-good")
            + "not json at all\n"
            + #"{"type":"assistant","message":{"model":"claude-truncated","usage":{"input_tokens":5"# + "\n"
            + #"{"type":"assistant","isSidechain":"no","message":{"model":"claude-bad-flag","usage":{"input_tokens":5}}}"# + "\n"
            + #"{"type":"assistant","message":{"model":"claude-bad-count","usage":{"input_tokens":"five"}}}"# + "\n"
            + #"{"type":"assistant","message":"claude-message-is-a-string","usage":{"input_tokens":5}}"# + "\n"
            + #"["assistant","usage"]"# + "\n"
            + "\n\n"
        let usage = try #require(try Self.read(text))
        #expect(usage.model == "claude-good")
    }

    /// Replaces `marker` in `line` with bytes that are not valid UTF-8.
    static func withInvalidUTF8(_ line: String, replacing marker: String) throws -> Data {
        var bytes = Data(line.utf8)
        let range = try #require(bytes.range(of: Data(marker.utf8)))
        bytes.replaceSubrange(range, with: [0xFF, 0xFE, 0xC0, 0x80])
        return bytes
    }

    @Test func invalidUTF8InIgnoredTextDoesNotHideTheUsage() throws {
        try withTempDirectory { tmp in
            let url = tmp.appendingPathComponent("session.jsonl")
            var bytes = Data(Fixture.assistant(model: "claude-earlier").utf8)
            bytes.append(try Self.withInvalidUTF8(Fixture.assistant(model: "claude-latest", text: "MARK"), replacing: "MARK"))
            try bytes.write(to: url)
            #expect(TranscriptContextReader().latestUsage(at: url)?.model == "claude-latest")
        }
    }

    @Test func invalidUTF8BreakingTheStructureIsSkipped() throws {
        try withTempDirectory { tmp in
            let url = tmp.appendingPathComponent("session.jsonl")
            var bytes = Data(Fixture.assistant(model: "claude-earlier").utf8)
            bytes.append(try Self.withInvalidUTF8(Fixture.assistant(model: "claude-latest"), replacing: #""message":"#))
            try bytes.write(to: url)
            #expect(TranscriptContextReader().latestUsage(at: url)?.model == "claude-earlier")
        }
    }

    @Test func crlfLineEndingsAreTolerated() throws {
        let text = Fixture.assistant(model: "claude-crlf").replacingOccurrences(of: "\n", with: "\r\n")
            + Fixture.user().replacingOccurrences(of: "\n", with: "\r\n")
        #expect(try Self.read(text)?.model == "claude-crlf")
    }

    @Test func completeFinalLineWithoutNewlineIsUsed() throws {
        var text = Fixture.assistant(model: "claude-first") + Fixture.assistant(model: "claude-last")
        text.removeLast()
        #expect(try Self.read(text)?.model == "claude-last")
    }

    @Test func halfWrittenFinalLineIsSkipped() throws {
        let partial = String(Fixture.assistant(model: "claude-in-progress").dropLast(30))
        let text = Fixture.assistant(model: "claude-first") + partial
        #expect(try Self.read(text)?.model == "claude-first")
    }

    @Test func hugeTokenCountsSaturateInsteadOfOverflowing() throws {
        let usage = try #require(try Self.read(Fixture.assistant(input: Int.max, cacheCreation: Int.max, cacheRead: 1, output: 1)))
        #expect(usage.usedTokens == Int.max)
    }

    @Test func negativeTokenCountsAreTreatedAsZero() throws {
        let usage = try #require(try Self.read(Fixture.assistant(input: -500, cacheCreation: 100, cacheRead: 0, output: 1)))
        #expect(usage.usedTokens == 101)
    }

    // MARK: Nothing usable

    @Test func emptyFileReturnsNil() throws {
        #expect(try Self.read("") == nil)
    }

    @Test func fileWithoutAssistantLinesReturnsNil() throws {
        #expect(try Self.read(Fixture.user() + Fixture.filler(bytes: 5_000)) == nil)
    }

    @Test func missingFileReturnsNil() throws {
        try withTempDirectory { tmp in
            #expect(TranscriptContextReader().latestUsage(at: tmp.appendingPathComponent("absent.jsonl")) == nil)
        }
    }

    @Test func directoryReturnsNil() throws {
        try withTempDirectory { tmp in
            #expect(TranscriptContextReader().latestUsage(at: tmp) == nil)
        }
    }

    @Test func nonFileURLReturnsNil() throws {
        let url = try #require(URL(string: "https://example.com/session.jsonl"))
        #expect(TranscriptContextReader().latestUsage(at: url) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func fifoReturnsNilWithoutBlocking() throws {
        try withTempDirectory { tmp in
            let fifo = tmp.appendingPathComponent("pipe.jsonl")
            #expect(mkfifo(fifo.path, 0o600) == 0)
            #expect(TranscriptContextReader().latestUsage(at: fifo) == nil)
        }
    }

    // MARK: Window growth (256 KB, ×4, max 8 MB)

    /// The spec's window sizes. With the tests below (nothing past the maximum window is found), this
    /// is what keeps an 80 MB transcript from being read whole: the performance tests' clock can't.
    @Test func windowSizesAreTheSpecs() {
        #expect(TranscriptTailScanner.initialWindow == 256 * 1_024)
        #expect(TranscriptTailScanner.growthFactor == 4)
        #expect(TranscriptTailScanner.maxWindow == 8 * 1_024 * 1_024)
    }

    @Test func growsTheWindowPastTrailingNonAssistantLines() throws {
        let text = Fixture.assistant(model: "claude-far-back") + Fixture.filler(bytes: 300 * 1_024)
        #expect(text.utf8.count > TranscriptTailScanner.initialWindow)
        #expect(try Self.read(text)?.model == "claude-far-back")
    }

    @Test func findsAnAssistantLineLongerThanTheInitialWindow() throws {
        let text = Fixture.user() + Fixture.assistant(model: "claude-long", text: String(repeating: "y", count: 400 * 1_024))
        #expect(try Self.read(text)?.model == "claude-long")
    }

    @Test func findsALineJustInsideTheMaximumWindow() throws {
        let text = Fixture.filler(bytes: 100_000)
            + Fixture.assistant(model: "claude-deep")
            + Fixture.filler(bytes: TranscriptTailScanner.maxWindow - 64 * 1_024)
        #expect(try Self.read(text)?.model == "claude-deep")
    }

    @Test func returnsNilWhenNothingUsableWithinTheMaximumWindow() throws {
        let text = Fixture.assistant(model: "claude-too-deep") + Fixture.filler(bytes: TranscriptTailScanner.maxWindow + 1_024)
        #expect(try Self.read(text) == nil)
    }

    // MARK: Partial first line

    /// The tail window starts inside a malformed line whose suffix happens to be a valid, usable
    /// assistant entry. That fragment must be ignored; the reader grows the window and finds the
    /// real entry before it.
    @Test func ignoresThePartialFirstLineOfTheWindow() throws {
        let fragment = Fixture.assistant(model: "claude-fragment")
        let spaces = 1_000
        let brokenLine = "#" + String(repeating: " ", count: spaces) + fragment
        // Put the window start in the middle of the spaces.
        let tailLength = TranscriptTailScanner.initialWindow - fragment.utf8.count - spaces / 2
        let text = Fixture.assistant(model: "claude-real") + brokenLine + Fixture.filler(bytes: tailLength)
        let windowStart = text.utf8.count - TranscriptTailScanner.initialWindow
        let brokenStart = text.utf8.count - tailLength - brokenLine.utf8.count
        #expect(windowStart > brokenStart + 1 && windowStart < brokenStart + 1 + spaces)

        #expect(try Self.read(text)?.model == "claude-real")
    }

    /// A line that starts exactly at the window start is complete and must be used, even when the
    /// window cannot grow any further.
    @Test func usesALineStartingExactlyAtTheWindowStart() throws {
        let target = Fixture.assistant(model: "claude-boundary")
        let tail = Fixture.filler(bytes: 300)
        let window = target.utf8.count + tail.utf8.count
        let reader = TranscriptContextReader(initialWindow: window, maxWindow: window)
        #expect(try Self.read(Fixture.assistant(model: "claude-earlier") + target + tail, reader: reader)?.model == "claude-boundary")
    }

    @Test func smallWindowsGrowUntilTheLineIsFound() throws {
        let text = Fixture.assistant(model: "claude-found") + Fixture.filler(bytes: 2_000, lineLength: 150)
        let reader = TranscriptContextReader(initialWindow: 64, maxWindow: 4_096)
        #expect(try Self.read(text, reader: reader)?.model == "claude-found")

        let tooSmall = TranscriptContextReader(initialWindow: 64, maxWindow: 1_024)
        #expect(try Self.read(text, reader: tooSmall) == nil)
    }
}
