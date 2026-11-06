import Foundation
import HeadroomModel

/// What the two-ring gauge draws (spec §1.1): outer ring = weekly, inner ring = 5-hour. For Codex and Copilot
/// (1.1 §6.1): outer = the longest window, inner = the 5-hour window, and no inner ring at all when the plan has
/// no 5-hour window, so it can't read as "5-hour 0 %".
public struct GaugeModel: Sendable, Equatable {
    public struct Ring: Sendable, Equatable {
        /// 0...1 of the circle, clockwise from 12 o'clock.
        public var fraction: Double
        public var severity: Severity

        public init(fraction: Double, severity: Severity) {
            self.fraction = fraction
            self.severity = severity
        }

        /// Nil when there is no reading or its percent is not a finite number.
        init?(_ reading: LimitReading?) {
            guard let reading else { return nil }
            self.init(percent: reading.usedPercent)
        }

        /// Nil without a limit or a known percent (Copilot without a plan: tracks only).
        init?(_ limit: ToolLimit?) {
            guard let percent = limit?.usedPercent else { return nil }
            self.init(percent: percent)
        }

        private init?(percent: Double) {
            guard let badge = PercentBadge(percent: percent, thresholds: .limits) else { return nil }
            self.init(fraction: min(100, max(0, percent)) / 100, severity: badge.severity)
        }
    }

    public var outer: Ring?
    public var inner: Ring?
    /// Draw everything at `HeadroomTheme.staleOpacity`.
    public var isStale: Bool
    /// Draw the inner ring's track. False for plans without a 5-hour window (Codex Pro, Copilot): only the outer
    /// ring is drawn (1.1 §6.1).
    public var showsInnerTrack: Bool

    public init(outer: Ring?, inner: Ring?, isStale: Bool, showsInnerTrack: Bool = true) {
        self.outer = outer
        self.inner = inner
        self.isStale = isStale
        self.showsInnerTrack = showsInnerTrack
    }

    public init(plan: PlanUsage, now: Date) {
        self.init(outer: Ring(plan.weekly), inner: Ring(plan.fiveHour), isStale: plan.isStale(now: now))
    }

    /// A tool's rings (1.1 §6.1): outer = its longest window (other than the 5-hour one when the plan has one),
    /// inner = its 5-hour window. Dimmed when stale, or when the last reading is kept because GitHub can't be
    /// reached (`ToolText.isDimmed`).
    public init(usage: ToolUsage, now: Date) {
        let hasFiveHour = usage.hasFiveHourWindow
        let outer = usage.limits.first { !(hasFiveHour && $0.window == .fiveHour) }
        self.init(
            outer: Ring(outer),
            inner: hasFiveHour ? Ring(usage.limit(.fiveHour)) : nil,
            isStale: ToolText.isDimmed(usage, now: now),
            showsInnerTrack: hasFiveHour
        )
    }

    /// Only the tracks are drawn.
    public var hasNoData: Bool { outer == nil && inner == nil }
}
