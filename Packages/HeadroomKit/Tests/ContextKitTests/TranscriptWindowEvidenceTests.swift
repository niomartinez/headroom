import Foundation
import HeadroomModel
import Testing
@testable import ContextKit

/// F01: a model's 1M window is learned from its own replies above 200k tokens, so a session below 200k
/// (after a compaction, or just before crossing it) is not shown as a percentage of a guessed 200k.
@Suite("Window evidence from transcripts (spec §2.3)")
struct TranscriptWindowEvidenceTests {
    /// A main-thread (or sidechain) reply from `model` that used exactly `tokens` tokens.
    static func reply(_ model: String, _ tokens: Int, sidechain: Bool = false) -> String {
        Fixture.assistant(model: model, input: 4, cacheCreation: 1_000, cacheRead: tokens - 1_104, output: 100, sidechain: sidechain)
    }

    static func window(for usage: TranscriptUsage?) -> Int? {
        usage.map { ContextWindowResolver.contextUsage(for: $0, exactFromStatusLine: nil, learned: [:]).windowTokens }
    }

    // MARK: The reproduced sessions

    @Test func reproducedSessionsBelow200kGetTheirMillionTokenWindow() throws {
        try withTempDirectory { tmp in
            let fable = tmp.appendingPathComponent("fable.jsonl")
            let opus = tmp.appendingPathComponent("opus.jsonl")
            try fable.write(Self.reply("claude-fable-5-1", 162_875) + Fixture.user() + Self.reply("claude-fable-5-1", 168_236))
            try opus.write(Self.reply("claude-opus-4-8", 198_505) + Fixture.user() + Self.reply("claude-opus-4-8", 199_556))
            let reader = TranscriptContextReader()

            let fableUsage = try #require(reader.latestUsage(at: fable))
            let fableContext = ContextWindowResolver.contextUsage(for: fableUsage, exactFromStatusLine: nil, learned: [:])
            #expect(fableContext.usedTokens == 168_236)
            #expect(fableContext.windowTokens == 1_000_000)
            #expect((fableContext.percent * 10).rounded() == 168)

            let opusUsage = try #require(reader.latestUsage(at: opus))
            let opusContext = ContextWindowResolver.contextUsage(for: opusUsage, exactFromStatusLine: nil, learned: [:])
            #expect(opusContext.usedTokens == 199_556)
            #expect(opusContext.windowTokens == 1_000_000)
            #expect(opusContext.percent < 20)
        }
    }

    // MARK: Earlier in the same transcript

    @Test func anEarlierReplyAbove200kInTheSameTranscriptCounts() throws {
        let text = Self.reply("claude-sonnet-4-6", 450_000) + Fixture.user(text: "compacted")
            + Self.reply("claude-sonnet-4-6", 60_000) + Fixture.user()
        let usage = try #require(try TranscriptTailReadingTests.read(text))
        #expect(usage.usedTokens == 60_000)
        #expect(usage.modelExceededStandardWindow)
        #expect(Self.window(for: usage) == 1_000_000)
    }

    @Test func earlierRepliesAtOrBelow200kAreNotEvidence() throws {
        let text = Self.reply("claude-sonnet-4-6", 200_000) + Self.reply("claude-sonnet-4-6", 150_000)
        let usage = try #require(try TranscriptTailReadingTests.read(text))
        #expect(!usage.modelExceededStandardWindow)
        #expect(Self.window(for: usage) == 200_000)
    }

    @Test func sidechainRepliesAreNotEvidence() throws {
        let text = Self.reply("claude-sonnet-4-6", 450_000, sidechain: true) + Self.reply("claude-sonnet-4-6", 60_000)
        let usage = try #require(try TranscriptTailReadingTests.read(text))
        #expect(!usage.modelExceededStandardWindow)
        #expect(Self.window(for: usage) == 200_000)
    }

    @Test func anotherModelAbove200kSaysNothingAboutThisOne() throws {
        let text = Self.reply("claude-other-model", 450_000) + Self.reply("claude-sonnet-4-6", 60_000)
        let usage = try #require(try TranscriptTailReadingTests.read(text))
        #expect(!usage.modelExceededStandardWindow)
        #expect(Self.window(for: usage) == 200_000)
    }

    @Test func aReplyAbove200kTeachesItsModelEvenWhenOlderThanTheNewest() throws {
        try withTempDirectory { tmp in
            let mixed = tmp.appendingPathComponent("mixed.jsonl")
            let other = tmp.appendingPathComponent("other.jsonl")
            try mixed.write(Self.reply("claude-other-model", 450_000) + Self.reply("claude-sonnet-4-6", 60_000))
            try other.write(Self.reply("claude-other-model", 90_000))
            let reader = TranscriptContextReader()
            #expect(reader.latestUsage(at: mixed)?.modelExceededStandardWindow == false)
            #expect(reader.latestUsage(at: other)?.modelExceededStandardWindow == true)
        }
    }

    // MARK: Across polls and transcripts

    @Test func evidenceCarriesAcrossTranscripts() throws {
        try withTempDirectory { tmp in
            let before = tmp.appendingPathComponent("before.jsonl")
            let now = tmp.appendingPathComponent("now.jsonl")
            try before.write(Self.reply("claude-sonnet-4-6", 300_000))
            try now.write(Self.reply("claude-sonnet-4-6", 120_000))
            let reader = TranscriptContextReader()
            #expect(reader.latestUsage(at: before)?.modelExceededStandardWindow == true)
            let usage = try #require(reader.latestUsage(at: now))
            #expect(usage.modelExceededStandardWindow)
            #expect(Self.window(for: usage) == 1_000_000)
        }
    }

    @Test func evidenceReachesResultsAlreadyCached() throws {
        try withTempDirectory { tmp in
            let now = tmp.appendingPathComponent("now.jsonl")
            let other = tmp.appendingPathComponent("other.jsonl")
            try now.write(Self.reply("claude-sonnet-4-6", 120_000))
            try other.write(Self.reply("claude-sonnet-4-6", 640_000))
            let reader = TranscriptContextReader()
            #expect(reader.latestUsage(at: now)?.modelExceededStandardWindow == false)
            #expect(reader.latestUsage(at: other)?.modelExceededStandardWindow == true)
            #expect(reader.latestUsage(at: now)?.modelExceededStandardWindow == true)
            #expect(reader.readCount == 2)
        }
    }

    /// The reply above 200k has left the tail window by the next poll; the reader still remembers it.
    @Test func evidenceCarriesAcrossPollsOfOneTranscript() throws {
        try withTempDirectory { tmp in
            let url = tmp.appendingPathComponent("session.jsonl")
            try url.write(Self.reply("claude-sonnet-4-6", 250_000))
            let reader = TranscriptContextReader(initialWindow: 1_024, maxWindow: 4_096)
            #expect(reader.latestUsage(at: url)?.modelExceededStandardWindow == true)

            try url.append(Fixture.filler(bytes: 20_000) + Self.reply("claude-sonnet-4-6", 40_000))
            let usage = try #require(reader.latestUsage(at: url))
            #expect(usage.usedTokens == 40_000)
            #expect(usage.modelExceededStandardWindow)
            #expect(reader.readCount == 2)
        }
    }

    @Test func modelIdsMatchIgnoringCase() throws {
        try withTempDirectory { tmp in
            let before = tmp.appendingPathComponent("before.jsonl")
            let now = tmp.appendingPathComponent("now.jsonl")
            try before.write(Self.reply("Claude-Sonnet-4-6", 300_000))
            try now.write(Self.reply("claude-sonnet-4-6", 120_000))
            let reader = TranscriptContextReader()
            _ = reader.latestUsage(at: before)
            #expect(reader.latestUsage(at: now)?.modelExceededStandardWindow == true)
        }
    }

    @Test func readersDoNotShareEvidence() throws {
        try withTempDirectory { tmp in
            let before = tmp.appendingPathComponent("before.jsonl")
            let now = tmp.appendingPathComponent("now.jsonl")
            try before.write(Self.reply("claude-sonnet-4-6", 300_000))
            try now.write(Self.reply("claude-sonnet-4-6", 120_000))
            _ = TranscriptContextReader().latestUsage(at: before)
            #expect(TranscriptContextReader().latestUsage(at: now)?.modelExceededStandardWindow == false)
        }
    }

    @Test func evidenceIsBounded() {
        let evidence = ModelWindowEvidence(limit: 2)
        for model in ["claude-a", "claude-b"] {
            evidence.record(TranscriptUsage(usedTokens: 300_000, model: model, timestamp: nil))
        }
        #expect(evidence.contains(model: "claude-a") && evidence.contains(model: "claude-b"))
        evidence.record(TranscriptUsage(usedTokens: 300_000, model: "claude-c", timestamp: nil))
        #expect(evidence.contains(model: "claude-c"))
        #expect(!evidence.contains(model: "claude-a"))
        #expect(!evidence.contains(model: nil))
    }
}
