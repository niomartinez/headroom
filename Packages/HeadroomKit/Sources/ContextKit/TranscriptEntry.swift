import Foundation

/// The fields of one transcript line that matter for context usage (spec §2.3). Everything else
/// in the line is ignored; a line whose known fields have the wrong type fails to decode and is skipped.
struct TranscriptEntry: Decodable {
    var type: String?
    var isSidechain: Bool?
    var timestamp: String?
    var message: Message?

    struct Message: Decodable {
        var model: String?
        var usage: Usage?
    }

    struct Usage: Decodable {
        var input: Int?
        var cacheCreationInput: Int?
        var cacheReadInput: Int?
        var output: Int?

        enum CodingKeys: String, CodingKey {
            case input = "input_tokens"
            case cacheCreationInput = "cache_creation_input_tokens"
            case cacheReadInput = "cache_read_input_tokens"
            case output = "output_tokens"
        }

        /// The sum of the counts present (negative counts as zero), saturating instead of
        /// overflowing. Nil when no count is present.
        var totalTokens: Int? {
            let counts = [input, cacheCreationInput, cacheReadInput, output].compactMap { $0 }
            guard !counts.isEmpty else { return nil }
            return counts.reduce(0) { total, count in
                let (sum, overflow) = total.addingReportingOverflow(max(0, count))
                return overflow ? .max : sum
            }
        }
    }

    /// What this entry says about the context, or nil unless it is a main-thread assistant reply
    /// with usage from a real model.
    var usage: TranscriptUsage? {
        guard type == "assistant", isSidechain != true,
              let message, message.model != "<synthetic>",
              let tokens = message.usage?.totalTokens
        else { return nil }
        return TranscriptUsage(usedTokens: tokens, model: message.model, timestamp: timestamp.flatMap(Self.date(fromISO8601:)))
    }

    /// Accepts ISO-8601 timestamps with or without fractional seconds.
    static func date(fromISO8601 text: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(text)
    }
}
