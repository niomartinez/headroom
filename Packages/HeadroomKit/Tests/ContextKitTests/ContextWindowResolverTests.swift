import Foundation
import HeadroomModel
import Testing
@testable import ContextKit

@Suite("ContextWindowResolver (spec §2.3 window size)")
struct ContextWindowResolverTests {
    typealias Basis = ContextWindowResolver.WindowBasis

    struct Case: Sendable, CustomTestStringConvertible {
        var label: String
        var model: String?
        var used: Int = 50_000
        var exact: Int?
        var learned: [String: Int] = [:]
        /// A main-thread reply from this model used more than 200k tokens somewhere.
        var exceeded = false
        var tokens: Int
        var basis: Basis
        var testDescription: String { label }
    }

    static let cases: [Case] = [
        Case(label: "exact status-line size wins over everything", model: "claude-opus-5-5[1m]", used: 900_000,
             exact: 123_456, learned: ["claude-opus-5-5[1m]": 500_000], exceeded: true, tokens: 123_456, basis: .statusLine),
        Case(label: "non-positive exact size is ignored", model: "claude-haiku-4-5", exact: 0, tokens: 200_000, basis: .modelFamily),
        Case(label: "learned size for the same model", model: "claude-haiku-4-5",
             learned: ["claude-haiku-4-5": 400_000], tokens: 400_000, basis: .learnedForModel),
        Case(label: "learned size beats the [1m] suffix", model: "claude-test[1m]",
             learned: ["claude-test[1m]": 500_000], tokens: 500_000, basis: .learnedForModel),
        Case(label: "learned size for another model is ignored", model: "claude-haiku-4-5",
             learned: ["claude-other": 400_000], tokens: 200_000, basis: .modelFamily),
        Case(label: "non-positive learned size is ignored", model: "claude-haiku-4-5",
             learned: ["claude-haiku-4-5": -1], tokens: 200_000, basis: .modelFamily),
        Case(label: "[1m] suffix", model: "claude-haiku-4-5[1m]", tokens: 1_000_000, basis: .modelIdSuffix),
        Case(label: "[1M] suffix, any case", model: "claude-haiku-4-5[1M]", tokens: 1_000_000, basis: .modelIdSuffix),
        Case(label: "more than 200k used", model: "claude-haiku-4-5", used: 200_001, tokens: 1_000_000, basis: .observedUsage),
        Case(label: "exactly 200k used", model: "claude-haiku-4-5", used: 200_000, tokens: 200_000, basis: .modelFamily),
        Case(label: "more than 200k used, unknown model", model: nil, used: 250_000, tokens: 1_000_000, basis: .observedUsage),
        Case(label: "opus-5 family", model: "claude-opus-5-5", tokens: 1_000_000, basis: .modelFamily),
        Case(label: "sonnet-5 family", model: "claude-sonnet-5", tokens: 1_000_000, basis: .modelFamily),
        // F01: 1M-context models whose ids name neither opus-5 nor sonnet-5, below 200k tokens.
        Case(label: "fable-5.1 at 168,236 tokens", model: "claude-fable-5-1", used: 168_236, tokens: 1_000_000, basis: .modelFamily),
        Case(label: "fable-5 family", model: "claude-fable-5", tokens: 1_000_000, basis: .modelFamily),
        Case(label: "mythos-5 family", model: "claude-mythos-5-1", tokens: 1_000_000, basis: .modelFamily),
        Case(label: "opus-4-8 at 199,556 tokens", model: "claude-opus-4-8", used: 199_556, tokens: 1_000_000, basis: .modelFamily),
        Case(label: "opus-4-7", model: "claude-opus-4-7", tokens: 1_000_000, basis: .modelFamily),
        Case(label: "opus-4-6", model: "claude-opus-4-6", tokens: 1_000_000, basis: .modelFamily),
        Case(label: "family match ignores case", model: "Claude-Fable-5-1", tokens: 1_000_000, basis: .modelFamily),
        Case(label: "provider-prefixed id", model: "us.anthropic.claude-opus-4-8-v1:0", tokens: 1_000_000, basis: .modelFamily),
        Case(label: "haiku 4.5", model: "claude-haiku-4-5-20251001", tokens: 200_000, basis: .modelFamily),
        Case(label: "haiku 3.5", model: "claude-3-5-haiku-20241022", tokens: 200_000, basis: .modelFamily),
        Case(label: "older opus", model: "claude-opus-4-1", tokens: 200_000, basis: .assumed),
        Case(label: "opus-4-5", model: "claude-opus-4-5", tokens: 200_000, basis: .assumed),
        Case(label: "sonnet-4-6, 1M only on request", model: "claude-sonnet-4-6", tokens: 200_000, basis: .assumed),
        Case(label: "unknown model", model: nil, tokens: 200_000, basis: .assumed),
        // F01: evidence that the model has run above 200k (earlier in this transcript, or in another one).
        Case(label: "model seen above 200k before", model: "claude-sonnet-4-6", used: 150_000, exceeded: true,
             tokens: 1_000_000, basis: .observedUsage),
        Case(label: "unknown id seen above 200k before", model: "claude-future-6", used: 20_000, exceeded: true,
             tokens: 1_000_000, basis: .observedUsage),
        Case(label: "evidence beats the standard family", model: "claude-haiku-4-5", exceeded: true,
             tokens: 1_000_000, basis: .observedUsage),
        Case(label: "learned size beats evidence", model: "claude-sonnet-4-6", learned: ["claude-sonnet-4-6": 400_000],
             exceeded: true, tokens: 400_000, basis: .learnedForModel),
    ]

    @Test(arguments: cases)
    func firstMatchWins(_ c: Case) {
        let window = ContextWindowResolver.window(
            model: c.model, usedTokens: c.used, exactFromStatusLine: c.exact, learned: c.learned,
            modelExceededStandardWindow: c.exceeded
        )
        #expect(window.tokens == c.tokens)
        #expect(window.basis == c.basis)
        #expect(window.isExact == (c.basis == .statusLine))

        let result = ContextWindowResolver.windowTokens(
            model: c.model, usedTokens: c.used, exactFromStatusLine: c.exact, learned: c.learned,
            modelExceededStandardWindow: c.exceeded
        )
        #expect(result.tokens == c.tokens)
        #expect(result.exact == window.isExact)
    }

    @Test func windowTokensWithoutEvidenceKeepsItsOldSignature() {
        let result = ContextWindowResolver.windowTokens(
            model: "claude-sonnet-4-6", usedTokens: 150_000, exactFromStatusLine: nil, learned: [:]
        )
        #expect(result.tokens == 200_000)
        #expect(!result.exact)
    }

    @Test func contextUsageCombinesTranscriptAndWindow() {
        let transcript = TranscriptUsage(usedTokens: 250_000, model: "claude-opus-5-5", timestamp: Fixture.timestampDate)
        let usage = ContextWindowResolver.contextUsage(for: transcript, exactFromStatusLine: nil, learned: [:])
        #expect(usage == ContextUsage(usedTokens: 250_000, windowTokens: 1_000_000, model: "claude-opus-5-5",
                                      windowIsExact: false, observedAt: Fixture.timestampDate))
        #expect(usage.percent == 25)

        let exact = ContextWindowResolver.contextUsage(for: transcript, exactFromStatusLine: 500_000, learned: [:])
        #expect(exact.windowTokens == 500_000)
        #expect(exact.windowIsExact)
    }

    @Test func contextUsageUsesTheTranscriptsEvidence() {
        let plain = TranscriptUsage(usedTokens: 168_236, model: "claude-sonnet-4-6", timestamp: nil)
        #expect(ContextWindowResolver.contextUsage(for: plain, exactFromStatusLine: nil, learned: [:]).windowTokens == 200_000)

        let seen = TranscriptUsage(usedTokens: 168_236, model: "claude-sonnet-4-6", timestamp: nil, modelExceededStandardWindow: true)
        let usage = ContextWindowResolver.contextUsage(for: seen, exactFromStatusLine: nil, learned: [:])
        #expect(usage.windowTokens == 1_000_000)
        #expect(!usage.windowIsExact)
    }

    /// Only a window no rule decided is marked assumed, so the UI shows its token count without a percent.
    @Test(arguments: cases)
    func contextUsageMarksOnlyAnAssumedWindow(_ c: Case) {
        let transcript = TranscriptUsage(
            usedTokens: c.used, model: c.model, timestamp: nil, modelExceededStandardWindow: c.exceeded
        )
        let usage = ContextWindowResolver.contextUsage(for: transcript, exactFromStatusLine: c.exact, learned: c.learned)
        #expect(usage.windowIsAssumed == (c.basis == .assumed))
        #expect(usage.windowTokens == c.tokens)
    }

    @Test func unknownModelBelowTheStandardWindowIsAssumed() {
        let transcript = TranscriptUsage(usedTokens: 168_236, model: "claude-opus-4-5", timestamp: Fixture.timestampDate)
        let usage = ContextWindowResolver.contextUsage(for: transcript, exactFromStatusLine: nil, learned: [:])
        #expect(usage == ContextUsage(
            usedTokens: 168_236, windowTokens: 200_000, model: "claude-opus-4-5", windowIsExact: false,
            observedAt: Fixture.timestampDate, windowIsAssumed: true
        ))
    }
}
