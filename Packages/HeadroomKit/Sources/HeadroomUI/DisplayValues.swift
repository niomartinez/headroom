import Foundation
import HeadroomModel

/// The status dot (spec §1.1): pulsing green, steady amber or steady gray.
public enum DotState: Sendable, Equatable {
    case working
    case waiting
    case idle

    public init(_ activity: SessionActivity) {
        switch activity {
        case .working: self = .working
        case .waitingForInput: self = .waiting
        case .idle: self = .idle
        }
    }

    /// The state in words, for VoiceOver: the dot's color alone says nothing.
    var spokenState: String {
        switch self {
        case .working: "working"
        case .waiting: "needs input"
        case .idle: "idle"
        }
    }

    /// Waiting wins over working, working over idle.
    public init(sessions: [SessionInfo]) {
        if sessions.contains(where: { $0.activity == .waitingForInput }) {
            self = .waiting
        } else if sessions.contains(where: { $0.activity == .working }) {
            self = .working
        } else {
            self = .idle
        }
    }
}

/// A percentage as shown: rounded text plus the severity that colors it.
public struct PercentBadge: Sendable, Equatable {
    public var text: String
    public var severity: Severity

    public init(text: String, severity: Severity) {
        self.text = text
        self.severity = severity
    }

    /// Severity is judged on the displayed (rounded) number so text and color always agree.
    /// Nil for non-finite input.
    public init?(percent: Double, thresholds: Thresholds) {
        guard let rounded = HeadroomFormat.roundedPercent(percent) else { return nil }
        self.init(text: "\(rounded)%", severity: thresholds.severity(for: Double(rounded)))
    }
}

/// A session's context bar and percentage (spec §1.2).
public struct ContextBadge: Sendable, Equatable {
    /// 0...1, the bar fill.
    public var fraction: Double
    /// "72%", or the token count ("168k") when the window size is a guess.
    public var text: String
    public var severity: Severity
    /// The window size is a guess (`ContextUsage.windowIsAssumed`): `text` is the token count, the
    /// bar is empty and the severity neutral, since a percent of a guessed window would mislead.
    public var windowIsAssumed: Bool

    public init(fraction: Double, text: String, severity: Severity, windowIsAssumed: Bool = false) {
        self.fraction = fraction
        self.text = text
        self.severity = severity
        self.windowIsAssumed = windowIsAssumed
    }

    init?(_ context: ContextUsage, format: HeadroomFormat) {
        if context.windowIsAssumed {
            self.init(fraction: 0, text: format.tokenCount(context.usedTokens), severity: .normal, windowIsAssumed: true)
            return
        }
        guard context.windowTokens > 0, let badge = PercentBadge(percent: context.percent, thresholds: .context) else { return nil }
        // With a baseline (Codex) the bar follows the tool's own percent, which leaves the baseline out (1.1 §3.5).
        let fraction = context.baselineTokens > 0
            ? context.percent / 100
            : Double(max(0, context.usedTokens)) / Double(context.windowTokens)
        self.init(fraction: min(1, fraction), text: badge.text, severity: badge.severity)
    }
}

extension PlanUsage {
    /// Spec §1.1: stale when the newest reading is older than 30 minutes.
    func isStale(now: Date) -> Bool {
        guard let newest = newestObservation else { return false }
        return now.timeIntervalSince(newest) > PlanUsage.staleAfter
    }
}

extension String {
    /// Trimmed, or `fallback` when blank.
    func nonBlank(or fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
