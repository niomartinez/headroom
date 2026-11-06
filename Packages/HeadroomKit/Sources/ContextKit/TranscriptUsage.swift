import Foundation

/// The newest usable assistant entry in a transcript.
public struct TranscriptUsage: Sendable, Equatable {
    /// input + cache_creation_input + cache_read_input + output tokens.
    public var usedTokens: Int
    public var model: String?
    public var timestamp: Date?
    /// Whether a main-thread reply from `model` has used more than the standard 200k-token window
    /// (spec §2.3): this one, an earlier one in this transcript, or one in any other transcript the
    /// `TranscriptContextReader` that returned this value has read. Evidence that the model runs with a
    /// 1M window here even while this session is below 200k.
    public var modelExceededStandardWindow: Bool

    public init(usedTokens: Int, model: String?, timestamp: Date?, modelExceededStandardWindow: Bool = false) {
        self.usedTokens = usedTokens
        self.model = model
        self.timestamp = timestamp
        self.modelExceededStandardWindow = modelExceededStandardWindow
    }
}
