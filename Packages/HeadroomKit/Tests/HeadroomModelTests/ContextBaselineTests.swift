import Foundation
import Testing
@testable import HeadroomModel

/// Codex's own context percent: `clamp(max(0, used − B) / (W − B))` with B = 12,000 (1.1 §3.5).
@Suite struct ContextBaselineTests {
    private func context(used: Int, window: Int = 258_400, baseline: Int = 12_000) -> ContextUsage {
        ContextUsage(usedTokens: used, windowTokens: window, model: nil, windowIsExact: true, observedAt: nil,
                     baselineTokens: baseline)
    }

    @Test func baselineIsLeftOut() {
        #expect(context(used: 150_000).percent == Double(138_000) / Double(246_400) * 100)
        #expect(context(used: 12_000 + 123_200).percent == 50)
    }

    @Test func clampsBothWays() {
        // Codex reaches ~105 % before auto-compaction.
        #expect(context(used: 272_000).percent == 100)
        #expect(context(used: 5_000).percent == 0)
        #expect(context(used: 12_000).percent == 0)
    }

    @Test func windowNoLargerThanTheBaselineIsZero() {
        #expect(context(used: 50_000, window: 12_000).percent == 0)
        #expect(context(used: 50_000, window: 0).percent == 0)
    }

    @Test func noBaselineKeepsTheClaudeFormula() {
        #expect(context(used: 50_000, window: 200_000, baseline: 0).percent == 25)
        #expect(ContextUsage(usedTokens: 50_000, windowTokens: 200_000, model: nil, windowIsExact: true,
                             observedAt: nil).baselineTokens == 0)
    }

    @Test func baselineRoundTripsAndDefaultsToZero() throws {
        let codex = context(used: 150_000)
        #expect(try JSONDecoder().decode(ContextUsage.self, from: JSONEncoder().encode(codex)) == codex)
        let json = #"{"usedTokens":150000,"windowTokens":258400,"windowIsExact":true}"#
        #expect(try JSONDecoder().decode(ContextUsage.self, from: Data(json.utf8)).baselineTokens == 0)
    }
}
