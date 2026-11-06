import CoreGraphics
import Foundation
import HeadroomModel

/// Everything the menu bar pill shows, computed from a snapshot (spec §1.1, 1.1 §6.1). Pure: no SwiftUI.
public struct PillModel: Sendable, Equatable {
    /// One gauge of "One gauge per tool" (1.1 §6.1).
    public struct ToolGauge: Sendable, Equatable {
        public var tool: ToolID
        public var gauge: GaugeModel
        /// This tool's tightest limit, shown beside its gauge from 75 %.
        public var badge: PercentBadge?
    }

    public var dot: DotState
    /// Working + waiting sessions of every tracked tool; nil when 0 so the pill hides it.
    public var count: Int?
    /// The shown tool's tightest limit, only when it is at least 75 %. Per-tool gauges carry their own badges.
    public var badge: PercentBadge?
    /// The shown tool's rings.
    public var gauge: GaugeModel
    /// The tool the rings show (the resolved "Rings show"); nil when no tool is tracked.
    public var tool: ToolID?
    /// With "One gauge per tool" and two or more tools with limits: a gauge per tool, in display order. Else empty,
    /// and the pill draws `gauge`.
    public var toolGauges: [ToolGauge]
    /// The shown tool's newest reading is older than its stale age.
    public var isStale: Bool
    /// No usable limit reading: the gauge shows only its tracks.
    public var hasNoData: Bool
    /// Non-nil while a moment is announced: the widened layout.
    public var moment: MomentDisplay?
    /// Unseen sessions that need you (1.1 §14.4): the rest state "(!) harbor" when no moment is showing.
    public var attention: NeedsYouAttention?
    /// Sizes for the pill's height (1.1 §14.6).
    public var metrics: PillMetrics
    public var accessibilityLabel: String
    /// The status item's tooltip with more than Claude tracked: every tool's limits (1.1 §6.1). Nil with only
    /// Claude, as in 1.0.
    public var toolTip: String?
    /// Two or more tools are tracked: the gauge carries its tool's symbol, as each per-tool gauge does.
    public var marksGaugeTool: Bool

    /// Which layout the pill draws; `PillMotion` animates only between different ones.
    public enum Mode: Sendable, Equatable {
        /// Dot, count, gauge and number.
        case normal
        /// A moment's symbol and text, then the gauge (4 s).
        case moment
        /// The needs-you rest state: symbol and name (or "2 need you"), gauge and number.
        case attention
    }

    /// `tool` is the "Rings show" choice (nil = Automatic); a tool that isn't tracked falls back to Automatic
    /// (`RingsTool.resolve`). `gaugePerTool` is "One gauge per tool". `attention` is the needs-you rest state and
    /// `dismissedIDs` the waits the user dismissed, which leave the dot and the count (1.1 §14.4). `height` is the
    /// pill's height (1.1 §14.6; at least 22 pt, 1.0's, the default).
    public init(
        snapshot: HeadroomSnapshot,
        moment: Moment?,
        now: Date,
        tool: ToolID? = nil,
        gaugePerTool: Bool = false,
        attention: NeedsYouAttention? = nil,
        dismissedIDs: Set<String> = [],
        height: CGFloat = PillMetrics.minimumHeight
    ) {
        let sessions = snapshot.applyingDismissals(dismissedIDs)
        let active = sessions.activeCount
        let waiting = sessions.waitingCount
        let shown = RingsTool.resolve(tool, in: snapshot)

        dot = DotState(sessions: sessions.sessions)
        count = active > 0 ? active : nil
        self.tool = shown
        self.moment = moment.map { MomentDisplay($0, trackedTools: snapshot.trackedTools) }
        self.attention = attention
        metrics = PillMetrics(height: height)

        if let shown, shown != .claude, let usage = snapshot.usage(for: shown) {
            gauge = GaugeModel(usage: usage, now: now)
            isStale = gauge.isStale
            badge = Self.tightestBadge(usage.limits.compactMap(\.usedPercent))
        } else {
            let plan = snapshot.plan
            gauge = GaugeModel(plan: plan, now: now)
            isStale = !gauge.hasNoData && plan.isStale(now: now)
            badge = Self.tightestBadge([plan.weekly, plan.fiveHour].compactMap { $0?.usedPercent })
        }
        hasNoData = gauge.hasNoData
        marksGaugeTool = snapshot.isMultiTool

        let perTool = gaugePerTool ? RingsTool.toolsWithLimits(in: snapshot) : []
        if perTool.count > 1 {
            toolGauges = perTool.map {
                ToolGauge(tool: $0, gauge: Self.gauge(for: $0, in: snapshot, now: now),
                          badge: Self.tightestBadge(Self.percents(of: $0, in: snapshot)))
            }
        } else {
            toolGauges = []
        }

        if snapshot.trackedTools.isEmpty || snapshot.isClaudeOnly {
            accessibilityLabel = Self.accessibilityLabel(
                active: active, waiting: waiting, plan: snapshot.plan, isStale: isStale, moment: self.moment
            )
            toolTip = nil
        } else {
            let limits = Self.spokenLimits(snapshot, now: now)
            let sessions = Self.spokenSessions(active: active, waiting: waiting)
            var label = "\(sessions). \(limits)"
            if let moment = self.moment { label = "\(moment.spokenText). \(label)" }
            accessibilityLabel = label
            toolTip = limits
        }
        // VoiceOver: the status item's label starts with who needs you (1.1 §14.4), unless a moment says it.
        if self.moment == nil, let attention {
            accessibilityLabel = "\(attention.spoken). \(accessibilityLabel)"
        }
    }

    /// Draws one gauge per tool.
    public var isGaugePerTool: Bool { !toolGauges.isEmpty }

    /// The layout drawn: a moment wins over the rest state, which wins over the normal pill.
    public var mode: Mode {
        if moment != nil { return .moment }
        return attention == nil ? .normal : .attention
    }

    /// The rest state's name cap: narrower with one gauge per tool, which already widens the pill (1.1 §14.4).
    public var maxAttentionNameWidth: CGFloat {
        isGaugePerTool ? metrics.maxAttentionNameWidthPerTool : metrics.maxAttentionNameWidth
    }

    private static func gauge(for tool: ToolID, in snapshot: HeadroomSnapshot, now: Date) -> GaugeModel {
        if tool == .claude { return GaugeModel(plan: snapshot.plan, now: now) }
        return snapshot.usage(for: tool).map { GaugeModel(usage: $0, now: now) } ?? GaugeModel(outer: nil, inner: nil, isStale: false)
    }

    private static func percents(of tool: ToolID, in snapshot: HeadroomSnapshot) -> [Double] {
        if tool == .claude { return [snapshot.plan.weekly, snapshot.plan.fiveHour].compactMap { $0?.usedPercent } }
        return snapshot.usage(for: tool)?.limits.compactMap(\.usedPercent) ?? []
    }

    /// The highest percent as shown.
    private static func tightestPercent(_ percents: [Double]) -> Int? {
        percents.compactMap { HeadroomFormat.roundedPercent($0) }.max()
    }

    /// The number for the tightest percent, when it is at least 75 %.
    private static func badge(forTightest percent: Int) -> PercentBadge? {
        guard let badge = PercentBadge(percent: Double(percent), thresholds: .limits), badge.severity != .normal else { return nil }
        return badge
    }

    private static func tightestBadge(_ percents: [Double]) -> PercentBadge? {
        tightestPercent(percents).flatMap(badge(forTightest:))
    }

    private static func spokenSessions(active: Int, waiting: Int) -> String {
        var sessions = active == 0 ? "No active sessions" : "\(active) active session\(active == 1 ? "" : "s")"
        if waiting > 0 { sessions += ", \(waiting) \(waiting == 1 ? "needs" : "need") input" }
        return sessions
    }

    /// "Claude weekly 89%, 5-hour 14%. Codex weekly 94%. Copilot 34% of monthly credits." (1.1 §6.1)
    private static func spokenLimits(_ snapshot: HeadroomSnapshot, now: Date) -> String {
        let format = HeadroomFormat()
        let parts = snapshot.trackedTools.compactMap { tool -> String? in
            guard let usage = snapshot.usage(for: tool) else { return nil }
            return ToolText.spokenSummary(usage, issues: snapshot.issues, now: now, format: format)
        }
        return parts.isEmpty ? "No usage data." : parts.map { "\($0)." }.joined(separator: " ")
    }

    /// The 1.0 label, with only Claude tracked.
    private static func accessibilityLabel(active: Int, waiting: Int, plan: PlanUsage, isStale: Bool, moment: MomentDisplay?) -> String {
        let sessions = spokenSessions(active: active, waiting: waiting)
        let limits = [plan.weekly, plan.fiveHour].compactMap { reading -> String? in
            guard let reading, let percent = HeadroomFormat.roundedPercent(reading.usedPercent) else { return nil }
            return "\(reading.kind.title) \(percent)%"
        }
        var label = "\(sessions). \(limits.isEmpty ? "No usage data" : limits.joined(separator: ", "))."
        if isStale { label += " Usage data is out of date." }
        if let moment { label = "\(moment.text). \(label)" }
        return label
    }
}
