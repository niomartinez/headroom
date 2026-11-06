import HeadroomModel

public enum ContextWindowResolver {
    static let standardWindow = 200_000
    static let extendedWindow = 1_000_000

    /// Model families with a 1M window by default. For Fable 5, Mythos 5, Opus 5 and Sonnet 5 it is the only
    /// window; Claude Code runs Opus 4.6–4.8 with it too. Matched anywhere in the lowercased model id.
    static let extendedFamilies = ["fable-5", "mythos-5", "opus-5", "sonnet-5", "opus-4-6", "opus-4-7", "opus-4-8"]
    /// Model families whose window is the standard 200k.
    static let standardFamilies = ["haiku-4", "3-5-haiku", "3-haiku"]

    /// Which spec §2.3 rule decided a window size.
    public enum WindowBasis: Sendable, Equatable {
        /// `context_window_size` from the session's own status line: the only exact size.
        case statusLine
        /// A size a status line reported for the same model id.
        case learnedForModel
        /// A model id ending with `[1m]`.
        case modelIdSuffix
        /// More than 200k tokens used, now or by an earlier main-thread reply from the same model id.
        case observedUsage
        /// A model family whose window is known.
        case modelFamily
        /// Nothing is known about the model: the standard 200k is a guess.
        case assumed
    }

    public struct ContextWindow: Sendable, Equatable {
        public var tokens: Int
        public var basis: WindowBasis

        public init(tokens: Int, basis: WindowBasis) {
            self.tokens = tokens
            self.basis = basis
        }

        /// `true` when the size came from the session's own status line.
        public var isExact: Bool { basis == .statusLine }
    }

    /// Spec §2.3 window-size rules.
    ///
    /// First match wins: the session's own status-line size (the only exact one); a size learned for the
    /// same model id from any status line; a `[1m]` model id; more than 200k tokens used, now or (per
    /// `modelExceededStandardWindow`) by an earlier main-thread reply from the same model id; a model family
    /// with a known window (`extendedFamilies` 1M, `standardFamilies` 200k); otherwise 200k, assumed.
    /// Non-positive sizes are ignored.
    public static func window(
        model: String?,
        usedTokens: Int,
        exactFromStatusLine: Int?,
        learned: [String: Int],
        modelExceededStandardWindow: Bool = false
    ) -> ContextWindow {
        if let exactFromStatusLine, exactFromStatusLine > 0 {
            return ContextWindow(tokens: exactFromStatusLine, basis: .statusLine)
        }
        if let model, let size = learned[model], size > 0 {
            return ContextWindow(tokens: size, basis: .learnedForModel)
        }
        return window(model: model, usedTokens: usedTokens, modelExceededStandardWindow: modelExceededStandardWindow)
    }

    /// The rules that need nothing but the transcript: from the `[1m]` suffix on.
    static func window(model: String?, usedTokens: Int, modelExceededStandardWindow: Bool) -> ContextWindow {
        let id = model?.lowercased() ?? ""
        if id.hasSuffix("[1m]") {
            return ContextWindow(tokens: extendedWindow, basis: .modelIdSuffix)
        }
        if usedTokens > standardWindow || modelExceededStandardWindow {
            return ContextWindow(tokens: extendedWindow, basis: .observedUsage)
        }
        if extendedFamilies.contains(where: { id.contains($0) }) {
            return ContextWindow(tokens: extendedWindow, basis: .modelFamily)
        }
        if standardFamilies.contains(where: { id.contains($0) }) {
            return ContextWindow(tokens: standardWindow, basis: .modelFamily)
        }
        return ContextWindow(tokens: standardWindow, basis: .assumed)
    }

    /// Spec §2.3 window-size rules (see `window(model:usedTokens:exactFromStatusLine:learned:modelExceededStandardWindow:)`).
    /// Returns the size and whether it is exact.
    public static func windowTokens(
        model: String?,
        usedTokens: Int,
        exactFromStatusLine: Int?,
        learned: [String: Int],
        modelExceededStandardWindow: Bool = false
    ) -> (tokens: Int, exact: Bool) {
        let resolved = window(
            model: model,
            usedTokens: usedTokens,
            exactFromStatusLine: exactFromStatusLine,
            learned: learned,
            modelExceededStandardWindow: modelExceededStandardWindow
        )
        return (resolved.tokens, resolved.isExact)
    }

    /// Combines a transcript reading with its window size (spec §2.3). `windowIsAssumed` is set when no
    /// rule decided the size (`.assumed`).
    public static func contextUsage(
        for usage: TranscriptUsage,
        exactFromStatusLine: Int?,
        learned: [String: Int]
    ) -> ContextUsage {
        let resolved = window(
            model: usage.model,
            usedTokens: usage.usedTokens,
            exactFromStatusLine: exactFromStatusLine,
            learned: learned,
            modelExceededStandardWindow: usage.modelExceededStandardWindow
        )
        return ContextUsage(
            usedTokens: usage.usedTokens,
            windowTokens: resolved.tokens,
            model: usage.model,
            windowIsExact: resolved.isExact,
            observedAt: usage.timestamp,
            windowIsAssumed: resolved.basis == .assumed
        )
    }
}
