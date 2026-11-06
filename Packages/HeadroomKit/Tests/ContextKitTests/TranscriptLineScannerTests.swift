import Foundation
import Testing
@testable import ContextKit

/// The search of older lines for window evidence (spec §2.3, F01).
@Suite("TranscriptLineScanner older-reply search")
struct TranscriptLineScannerTests {
    static let near = TranscriptWindowEvidenceTests.reply("claude-sonnet-4-6", 300_000)
    static let far = TranscriptWindowEvidenceTests.reply("claude-other-model", 450_000)
    static let gap = Fixture.filler(bytes: 200)
    static let text = far + Fixture.filler(bytes: 2_000) + near
        + TranscriptWindowEvidenceTests.reply("claude-sonnet-4-6", 150_000) + gap
        + TranscriptWindowEvidenceTests.reply("claude-sonnet-4-6", 60_000)

    static func scan(limit: Int = TranscriptLineScanner.olderSearchLimit, search: Bool = true) -> TranscriptLineScanner.Result {
        TranscriptLineScanner.scan(Array(text.utf8), startsMidLine: false, olderSearchLimit: limit) { _ in search }
    }

    @Test func findsOlderRepliesAboveTheStandardWindowNewestFirst() {
        let result = Self.scan()
        #expect(result.usage?.usedTokens == 60_000)
        #expect(result.olderAboveStandardWindow.map(\.usedTokens) == [300_000, 450_000])
        #expect(result.olderAboveStandardWindow.map(\.model) == ["claude-sonnet-4-6", "claude-other-model"])
    }

    @Test func searchesOnlyWhenAsked() {
        #expect(Self.scan(search: false).olderAboveStandardWindow.isEmpty)
    }

    /// Lines starting more than `olderSearchLimit` bytes before the newest entry are not decoded.
    @Test func searchStopsAtTheLimit() {
        let reachesNear = Self.gap.utf8.count + TranscriptWindowEvidenceTests.reply("claude-sonnet-4-6", 150_000).utf8.count
            + Self.near.utf8.count
        #expect(Self.scan(limit: reachesNear).olderAboveStandardWindow.map(\.usedTokens) == [300_000])
        #expect(Self.scan(limit: reachesNear - 1).olderAboveStandardWindow.isEmpty)
    }

    @Test func aFragmentAtTheChunkStartIsNotSearched() {
        // Without its first byte, the far line is a fragment when the chunk starts mid-line.
        let chunk = Array(Self.text.utf8.dropFirst())
        let result = TranscriptLineScanner.scan(chunk, startsMidLine: true) { _ in true }
        #expect(result.olderAboveStandardWindow.map(\.usedTokens) == [300_000])
    }
}
