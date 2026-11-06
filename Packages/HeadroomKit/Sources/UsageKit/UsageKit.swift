import Foundation
import HeadroomModel

// UsageKit: plan limits from the Claude desktop app's usage history (spec §2.1) and the terminal
// status line (§2.4), reset inference (§3.2) and merging (§3.1).
//
// Pipeline: `DesktopUsageReader.readSamples()` → `DesktopUsageAnalyzer.currentUsage(samples:now:)`,
// `TerminalLimitsReader.read()`, then `PlanUsageResolver.resolve(...)` for what the UI shows.

/// One sample from `plan-usage-history.json` (spec §2.1).
public struct DesktopUsageSample: Sendable, Equatable {
    public var time: Date
    public var org: String
    public var fiveHour: Double?
    public var weekly: Double?
    public var extra: Double?

    public init(time: Date, org: String, fiveHour: Double?, weekly: Double?, extra: Double?) {
        self.time = time
        self.org = org
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.extra = extra
    }

    func value(_ kind: LimitKind) -> Double? {
        switch kind {
        case .fiveHour: fiveHour
        case .weekly: weekly
        }
    }
}

public enum DesktopUsageError: Error, Equatable {
    /// The file does not exist or cannot be read.
    case fileMissing
    /// Unknown `version`, unexpected JSON shape, or implausibly large (→ `DataIssue.desktopUsageUnrecognized`).
    case unrecognizedFormat
}

extension Array where Element == DesktopUsageSample {
    /// Oldest first; samples with equal times keep their order.
    func sortedByTime() -> [DesktopUsageSample] {
        enumerated()
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map(\.element)
    }
}
