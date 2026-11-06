import Foundation
import HeadroomModel

/// What the panel says for a tool with nothing to count (1.1 §3.4, §4.6), and the button next to it.
public struct ToolStatusLine: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        /// "Settings…": Copilot is tracked but GitHub isn't connected. Opens Settings on the Tools tab.
        case openToolsSettings
        /// "Reconnect": the GitHub sign-in expired.
        case reconnectGitHub
    }

    /// "No Codex limits found", "Connect GitHub in Settings".
    public var message: String
    public var action: Action?

    public init(message: String, action: Action? = nil) {
        self.message = message
        self.action = action
    }

    public var actionTitle: String? {
        switch action {
        case .openToolsSettings: "Settings…"
        case .reconnectGitHub: "Reconnect"
        case nil: nil
        }
    }
}

/// "Rings show" (1.1 §6.1, §6.4): which tool the pill's rings, the panel's header and the widgets' Automatic show.
public enum RingsTool {
    /// Automatic: the first tracked tool, in the order Claude → Codex → Copilot, with a limit that has a percent;
    /// else the first tracked tool (its tracks only). Never the tightest tool, so the rings don't jump. Nil when
    /// no tool is tracked.
    public static func automatic(in snapshot: HeadroomSnapshot) -> ToolID? {
        let tracked = snapshot.trackedTools
        return tracked.first { hasPercent($0, in: snapshot) } ?? tracked.first
    }

    /// `choice` (nil = Automatic) when that tool is tracked, else Automatic.
    public static func resolve(_ choice: ToolID?, in snapshot: HeadroomSnapshot) -> ToolID? {
        if let choice, snapshot.trackedTools.contains(choice) { return choice }
        return automatic(in: snapshot)
    }

    /// The tracked tools with at least one limit, in display order: the gauges of "One gauge per tool".
    public static func toolsWithLimits(in snapshot: HeadroomSnapshot) -> [ToolID] {
        snapshot.trackedTools.filter { tool in
            tool == .claude ? !snapshot.plan.isEmpty : !(snapshot.usage(for: tool)?.limits.isEmpty ?? true)
        }
    }

    static func hasPercent(_ tool: ToolID, in snapshot: HeadroomSnapshot) -> Bool {
        if tool == .claude {
            return [snapshot.plan.weekly, snapshot.plan.fiveHour].contains { $0.map { $0.usedPercent.isFinite } ?? false }
        }
        return snapshot.usage(for: tool)?.limits.contains { $0.usedPercent?.isFinite ?? false } ?? false
    }
}

/// Codex and Copilot copy shared by the pill, the panel header and the compact tool rows (1.1 §4.6, §6).
enum ToolText {
    /// A limit reading is dimmed: stale while the tool may have been used since (1.1 §14.12), or kept while GitHub
    /// can't be reached (1.1 §4.6).
    static func isDimmed(_ usage: ToolUsage, now: Date) -> Bool {
        guard !usage.limits.isEmpty else { return false }
        return usage.isDimmedForAge(now: now) || usage.status == .offline || usage.status == .rateLimited
    }

    /// A reading says how old it is ("as of 2h ago"): dimmed, or stale but quiet since (1.1 §14.12).
    static func showsAge(_ usage: ToolUsage, now: Date) -> Bool {
        isDimmed(usage, now: now) || usage.isStale(now: now)
    }

    /// The message instead of limit rows; nil when the limits are shown, or the tool tracks only sessions.
    static func statusLine(_ usage: ToolUsage, issues: Set<DataIssue>) -> ToolStatusLine? {
        switch usage.status {
        case .sessionsOnly: return nil
        case .notConnected: return ToolStatusLine(message: "Connect GitHub in Settings", action: .openToolsSettings)
        case .signInExpired: return ToolStatusLine(message: "Sign-in expired", action: .reconnectGitHub)
        case .noIndividualUsage:
            // Not the login: a long one cut the compact row's message short. The row's hover names the account.
            return ToolStatusLine(message: "No usage billed to you this month")
        case .ok, .needsAccess, .noActivity, .unrecognized, .offline, .rateLimited: break
        }
        guard usage.limits.isEmpty else { return nil }
        let message = switch (usage.tool, usage.status) {
        case (.claude, _): issues.contains(.desktopUsageUnrecognized) ? "Usage data not recognized" : "No usage data yet"
        case (.codex, .needsAccess): "No access to ~/.codex"
        case (.codex, .unrecognized): "Codex usage data not recognized"
        case (.codex, _): "No Codex limits found"
        case (.copilot, .offline): "Can't reach GitHub"
        case (.copilot, .rateLimited): "GitHub is busy"
        case (.copilot, .unrecognized): "Copilot usage in an unknown format"
        case (.copilot, _): "No usage data yet"
        }
        return ToolStatusLine(message: message)
    }

    /// "credits" or "requests".
    static func unitName(_ unit: UsageUnit?) -> String {
        unit == .premiumRequests ? "requests" : "credits"
    }

    /// Copilot's amount: "512 of 1,500 credits", or "512 credits used" without a plan. Nil without an absolute
    /// amount (Codex, Claude).
    static func amount(_ limit: ToolLimit, format: HeadroomFormat) -> String? {
        guard let used = limit.used else { return nil }
        let unit = unitName(limit.unit)
        return limit.allowance.map { "\(format.amount(used)) of \(format.amount($0)) \(unit)" }
            ?? "\(format.amount(used)) \(unit) used"
    }

    /// "120 extra billed": Copilot usage billed beyond the plan (1.1 §4.6), appended after the amount.
    static func extraBilled(_ limit: ToolLimit, format: HeadroomFormat) -> String? {
        guard let extra = limit.extra, extra.isFinite, extra > 0 else { return nil }
        return "\(format.amount(extra)) extra billed"
    }

    /// Gray lines for Codex buckets other than "codex" at 75 % or more (1.1 §6.3): "GPT-5.3-Codex-Spark · weekly 80%".
    static func otherBucketNotes(_ usage: ToolUsage) -> [String] {
        usage.otherBuckets.compactMap { bucket in
            let tightest = bucket.limits
                .compactMap { limit in limit.usedPercent.flatMap(HeadroomFormat.roundedPercent).map { (limit, $0) } }
                .max { $0.1 < $1.1 }
            guard let (limit, percent) = tightest, percent >= Int(Thresholds.limits.warning) else { return nil }
            return "\(bucket.name) · \(limit.window.title.lowercased()) \(percent)%"
        }
    }

    /// A tool's limits for VoiceOver and the status item tooltip (1.1 §6.1): "Codex weekly 94%, 5-hour 20%",
    /// "Copilot 34% of monthly credits", "Copilot 512 credits used this month", "Copilot: Connect GitHub in
    /// Settings", with ", out of date" when dimmed. Nil for a tool that tracks only sessions.
    static func spokenSummary(_ usage: ToolUsage, issues: Set<DataIssue>, now: Date, format: HeadroomFormat) -> String? {
        if let status = statusLine(usage, issues: issues) {
            let name = usage.tool.shortName
            return status.message.contains(name) ? status.message : "\(name): \(status.message)"
        }
        guard !usage.limits.isEmpty else { return nil }
        let name = usage.tool.shortName
        var text: String
        if usage.tool == .copilot, let limit = usage.limits.first {
            let unit = unitName(limit.unit)
            let window = limit.window.title.lowercased()
            if let percent = limit.usedPercent.flatMap(HeadroomFormat.roundedPercent) {
                text = "\(name) \(percent)% of \(window) \(unit)"
            } else {
                text = "\(name) \(format.amount(limit.used ?? 0)) \(unit) used this \(window == "monthly" ? "month" : "period")"
            }
        } else {
            let limits = usage.limits.compactMap { limit -> String? in
                guard let percent = limit.usedPercent.flatMap(HeadroomFormat.roundedPercent) else { return nil }
                return "\(limit.window.title.lowercased()) \(percent)%"
            }
            text = "\(name) \(limits.joined(separator: ", "))"
        }
        if isDimmed(usage, now: now) { text += ", out of date" }
        return text
    }

    /// Hover text for a compact tool row (1.1 §6.3): the plan, each exact reset and how old the reading is. With no
    /// usage billed this month: the plan and account, and why an organization's plan doesn't show.
    static func helpText(_ usage: ToolUsage, now: Date, format: HeadroomFormat) -> String? {
        var lines: [String] = []
        let plan = [usage.planName.map { "\($0) plan" }, usage.account.map { "@\($0)" }].compactMap { $0 }
        if !plan.isEmpty { lines.append(plan.joined(separator: " · ")) }
        if usage.status == .noIndividualUsage { lines.append("Plans paid by an organization can't be read.") }
        for limit in usage.limits {
            if limit.resetSinceReading {
                lines.append("\(limit.window.title): \(HeadroomFormat.resetSinceReading)")
            } else if let resetsAt = limit.resetsAt, resetsAt > now {
                lines.append("\(limit.window.title) resets \(limit.resetIsEstimated ? "about " : "")\(format.exactDate(resetsAt))")
            }
        }
        if let observed = usage.newestObservation {
            lines.append("As of \(format.age(of: observed, now: now))")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
