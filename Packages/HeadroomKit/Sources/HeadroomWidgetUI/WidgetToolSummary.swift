import Foundation
import HeadroomModel
import HeadroomShare
import HeadroomUI

/// The line at the bottom of a widget (1.1 §5.6).
public struct WidgetFooter: Sendable, Equatable {
    public enum Tone: Sendable, Equatable {
        /// "Updated 2m ago": gray.
        case plain
        /// "Sample data": amber, as in the panel's footer.
        case sample
        /// "Headroom isn't running", "Open Headroom": something the user should act on.
        case attention
    }

    public var text: String
    public var tone: Tone

    public init(text: String, tone: Tone) {
        self.text = text
        self.tone = tone
    }

    public static let openHeadroom = WidgetFooter(text: "Open Headroom", tone: .attention)
    public static let notRunning = WidgetFooter(text: "Headroom isn't running", tone: .attention)
    public static let sample = WidgetFooter(text: "Sample data", tone: .sample)

    /// "Open Headroom" without a file, "Headroom isn't running" once it's 35 minutes old, "Sample data" in sample
    /// mode, else "Updated 2m ago" (the age of the app's last write).
    public init(file: WidgetSnapshotFile?, now: Date, format: HeadroomFormat) {
        guard let file else { self = .openHeadroom; return }
        if !file.isHeadroomRunning(at: now) {
            self = .notRunning
        } else if file.isSample {
            self = .sample
        } else {
            self.init(text: "Updated \(format.age(of: file.writtenAt, now: now))", tone: .plain)
        }
    }
}

/// One tool as the widgets draw it: its gauge and a row per limit, or a short status when there is no number to
/// show (1.1 §5.6, §6.3). Pure; built from a snapshot already rolled over to the entry's date.
public struct WidgetToolSummary: Sendable, Equatable, Identifiable {
    /// One limit: `Weekly … 89%` over `resets Sun 7 PM`.
    public struct Row: Sendable, Equatable {
        /// "Weekly", "5-hour", "Monthly".
        public var title: String
        /// What `value` counts when it is an amount instead of a percent (Copilot, plan not set): "credits used".
        public var amountLabel: String?
        /// The percent with its severity; nil when there is none.
        public var badge: PercentBadge?
        /// The rounded percent `badge` shows.
        public var percent: Int?
        /// "89%", an amount ("512") when there is no percent, or "–".
        public var value: String
        /// "resets Sun 7 PM", "resets in 2h 50m", "not started", "reset since last reading".
        public var reset: String
        /// "3h ago" when the reading is stale (or kept through an error), else nil.
        public var asOf: String?
        /// The row's ring for its ring key (1.1 §14.2): nil for tools whose gauge has one ring.
        public var ring: GaugeRing?

        public init(
            title: String, amountLabel: String? = nil, badge: PercentBadge?, percent: Int? = nil, value: String, reset: String,
            asOf: String?, ring: GaugeRing? = nil
        ) {
            self.title = title
            self.amountLabel = amountLabel
            self.badge = badge
            self.percent = percent
            self.value = value
            self.reset = reset
            self.asOf = asOf
            self.ring = ring
        }

        /// "resets Sun 7 PM · as of 3h ago"; "credits used · resets Oct 1" after an amount.
        public var detail: String {
            let detail = asOf.map { "\(reset) · as of \($0)" } ?? reset
            return amountLabel.map { "\($0) · \(detail)" } ?? detail
        }

        /// The small widget's and a column's bottom line: "as of 3h ago" when stale, else the reset.
        public var shortDetail: String {
            asOf.map { "as of \($0)" } ?? reset
        }

        /// "Weekly, 89% used, resets Sun 7 PM".
        var accessibilityText: String {
            let used = badge.map { "\($0.text) used" } ?? value
            return "\(title), \(used), \(detail)"
        }
    }

    public var tool: ToolID
    /// "Claude", "Codex", "Copilot".
    public var name: String
    public var gauge: GaugeModel
    /// False for tools without a 5-hour window (Codex Pro, Copilot): no inner track, so an empty ring can't read
    /// as "5-hour 0%" (§6.1).
    public var drawsInnerTrack: Bool
    /// Longest window first. Empty when `status` is set.
    public var rows: [Row]
    /// Copilot's absolute usage next to a percent: "512 of 1,500 credits".
    public var amount: String?
    /// "Not connected", "No limits found", "Not tracked": shown instead of rows.
    public var status: String?

    public var id: ToolID { tool }

    public init(
        tool: ToolID, gauge: GaugeModel, drawsInnerTrack: Bool, rows: [Row], amount: String? = nil, status: String? = nil
    ) {
        self.tool = tool
        name = tool.shortName
        self.gauge = gauge
        self.drawsInnerTrack = drawsInnerTrack
        self.rows = rows
        self.amount = amount
        self.status = status
    }

    /// The row with the highest percent (the longest window on a tie), else the first.
    public var tightestRow: Row? {
        rows.enumerated()
            .max { a, b in
                let pa = a.element.percent ?? -1
                let pb = b.element.percent ?? -1
                return pa != pb ? pa < pb : a.offset > b.offset
            }?
            .element
    }

    /// The outer ring's row (the longest window) and the inner ring's (5-hour), as the small widget stacks them.
    public var outerRow: Row? { rows.first }
    public var innerRow: Row? { drawsInnerTrack && rows.count > 1 ? rows.last : nil }

    /// Empty tracks and nothing else: no file, or a tool that isn't tracked.
    public static func placeholder(_ tool: ToolID, status: String? = nil) -> WidgetToolSummary {
        WidgetToolSummary(
            tool: tool, gauge: GaugeModel(outer: nil, inner: nil, isStale: false),
            drawsInnerTrack: tool != .copilot, rows: [], status: status
        )
    }

    /// The tool as `snapshot` has it at `now`, or nil when it isn't tracked or has no limits to show (Copilot
    /// tracked for CLI sessions only). `snapshot` must already be rolled over to `now`.
    public init?(tool: ToolID, snapshot: HeadroomSnapshot, now: Date, format: HeadroomFormat) {
        switch tool {
        case .claude:
            guard snapshot.claudeTracked else { return nil }
            self = Self.claude(snapshot, now: now, format: format)
        case .codex, .copilot:
            guard let usage = snapshot.usage(for: tool), usage.status != .sessionsOnly else { return nil }
            self = Self.other(usage, now: now, format: format)
        }
    }

    // MARK: Claude

    /// Claude always shows both rows, as the panel does: "no data yet" where a reading is missing.
    private static func claude(_ snapshot: HeadroomSnapshot, now: Date, format: HeadroomFormat) -> WidgetToolSummary {
        let usage = ToolUsage(claude: snapshot.plan)
        let noData = snapshot.issues.contains(.desktopUsageUnrecognized) ? "usage data not recognized" : "no data yet"
        let rows = [WindowKind.weekly, .fiveHour].map { window in
            var row = usage.limit(window).map { row($0, staleAfter: usage.staleAfter, forceAsOf: false, now: now, format: format) }
                ?? Row(title: window.title, badge: nil, value: "–", reset: noData, asOf: nil)
            row.ring = window == .fiveHour ? .inner : .outer
            return row
        }
        return WidgetToolSummary(
            tool: .claude, gauge: gauge(usage, now: now, forceStale: false), drawsInnerTrack: true, rows: rows
        )
    }

    // MARK: Codex and Copilot

    private static func other(_ usage: ToolUsage, now: Date, format: HeadroomFormat) -> WidgetToolSummary {
        // Offline or rate limited: the last reading stays, dimmed, with its age (§4.6).
        let keptThroughError = usage.status == .offline || usage.status == .rateLimited
        let showsNumbers = !usage.limits.isEmpty
            && [.ok, .offline, .rateLimited, .unrecognized].contains(usage.status)
        guard showsNumbers else {
            return WidgetToolSummary(
                tool: usage.tool, gauge: GaugeModel(outer: nil, inner: nil, isStale: false),
                drawsInnerTrack: usage.hasFiveHourWindow, rows: [], status: status(usage)
            )
        }
        let rows = usage.limits.map { limit in
            var row = row(limit, staleAfter: usage.staleAfter, forceAsOf: keptThroughError, now: now, format: format)
            if usage.hasFiveHourWindow { row.ring = limit.window == .fiveHour ? .inner : .outer }
            return row
        }
        return WidgetToolSummary(
            tool: usage.tool, gauge: gauge(usage, now: now, forceStale: keptThroughError),
            drawsInnerTrack: usage.hasFiveHourWindow, rows: rows,
            amount: usage.tool == .copilot ? amount(usage.limits.first, locale: format.locale) : nil
        )
    }

    /// Short, because a column is a third of a medium widget.
    private static func status(_ usage: ToolUsage) -> String {
        switch usage.status {
        case .needsAccess: "Needs access"
        case .noActivity: usage.tool == .codex ? "No limits found" : "No data yet"
        case .unrecognized: "Not recognized"
        case .notConnected: "Not connected"
        case .signInExpired: "Sign-in expired"
        case .noIndividualUsage: "No usage billed"
        case .ok, .offline, .rateLimited, .sessionsOnly: "No data yet"
        }
    }

    /// "512 of 1,500 credits" with an allowance; nil without one (the row's value then shows the amount).
    private static func amount(_ limit: ToolLimit?, locale: Locale) -> String? {
        guard let limit, let used = limit.used, let allowance = limit.allowance, allowance > 0 else { return nil }
        return "\(count(used, locale: locale)) of \(count(allowance, locale: locale)) \(unitName(limit.unit))"
    }

    // MARK: Rows and gauges

    /// Outer ring: the longest window that isn't 5-hour; inner ring: the 5-hour window, when the plan has one.
    private static func gauge(_ usage: ToolUsage, now: Date, forceStale: Bool) -> GaugeModel {
        let outer = usage.limits.first { $0.window != .fiveHour }
        let inner = usage.hasFiveHourWindow ? usage.limit(.fiveHour) : nil
        return GaugeModel(
            outer: ring(outer), inner: ring(inner),
            isStale: forceStale || usage.isDimmedForAge(now: now)
        )
    }

    private static func ring(_ limit: ToolLimit?) -> GaugeModel.Ring? {
        guard let percent = limit?.usedPercent, let badge = PercentBadge(percent: percent, thresholds: .limits) else {
            return nil
        }
        return GaugeModel.Ring(fraction: min(100, max(0, percent)) / 100, severity: badge.severity)
    }

    private static func row(
        _ limit: ToolLimit, staleAfter: TimeInterval, forceAsOf: Bool, now: Date, format: HeadroomFormat
    ) -> Row {
        let badge = limit.usedPercent.flatMap { PercentBadge(percent: $0, thresholds: .limits) }
        var value = badge?.text ?? "–"
        var amountLabel: String?
        if badge == nil, let used = limit.used {
            // Copilot with the plan not set: the amount instead of a percent (§4.5).
            value = count(used, locale: format.locale)
            amountLabel = "\(unitName(limit.unit)) used"
        }
        let isStale = forceAsOf || now.timeIntervalSince(limit.observedAt) > staleAfter
        return Row(
            title: limit.window.title, amountLabel: amountLabel, badge: badge,
            percent: limit.usedPercent.flatMap(HeadroomFormat.roundedPercent), value: value,
            reset: reset(limit, now: now, format: format),
            asOf: isStale ? format.age(of: limit.observedAt, now: now) : nil
        )
    }

    /// The panel's reset wording (spec §3.2, 1.1 §6.3).
    private static func reset(_ limit: ToolLimit, now: Date, format: HeadroomFormat) -> String {
        if limit.resetSinceReading { return "reset since last reading" }
        switch limit.window {
        case .fiveHour:
            let windowEndAhead = limit.resetsAt.map { $0 > now } ?? false
            // Usage without a window end ahead reads "reset unknown": "not started" would contradict the percent.
            if !windowEndAhead, let percent = limit.usedPercent, HeadroomFormat.roundedPercent(percent) != 0 {
                return HeadroomFormat.unknownReset
            }
            return format.fiveHourReset(at: limit.resetsAt, estimated: limit.resetIsEstimated, now: now)
        case .monthly where limit.unit != nil:
            guard let resetsAt = limit.resetsAt else { return HeadroomFormat.unknownReset }
            return "resets \(monthDay(resetsAt, locale: format.locale))"
        case .daily, .weekly, .monthly, .minutes:
            return format.weeklyReset(at: limit.resetsAt, estimated: limit.resetIsEstimated)
        }
    }

    /// "Oct 1": GitHub's month starts at 00:00 UTC, so the day is the UTC one GitHub's billing pages name.
    private static func monthDay(_ date: Date, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .month(.abbreviated)
            .day()
        return date.formatted(style)
    }

    /// "1,500": whole numbers, grouped.
    private static func count(_ value: Double, locale: Locale) -> String {
        guard value.isFinite, abs(value) < 1e12 else { return "–" }
        return Int(value.rounded()).formatted(.number.grouping(.automatic).locale(locale))
    }

    private static func unitName(_ unit: UsageUnit?) -> String {
        unit == .premiumRequests ? "requests" : "credits"
    }
}
