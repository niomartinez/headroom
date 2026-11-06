import Foundation
import HeadroomModel
@testable import HeadroomUI

/// Synthetic Codex and Copilot data (1.1): made-up values, no real ids or accounts.
extension Fixture {
    /// `en_US`, so Copilot amounts read "1,500" whatever the Mac's locale.
    static let usFormat = HeadroomFormat(calendar: calendar, timeZone: manila, locale: Locale(identifier: "en_US"))

    /// Wednesday 2026-09-30 09:00 Manila: the Codex weekly reset.
    static let codexWeeklyReset = date(2026, 9, 30, 9, 0)
    /// 2026-10-01 00:00 UTC = 08:00 Manila: GitHub's Copilot reset.
    static let copilotReset = Date(timeIntervalSince1970: 1_790_812_800)

    static func limit(
        _ window: WindowKind, _ percent: Double?, resetsAt: Date? = nil, age: TimeInterval = 300,
        used: Double? = nil, allowance: Double? = nil, extra: Double? = nil, unit: UsageUnit? = nil,
        resetSinceReading: Bool = false
    ) -> ToolLimit {
        ToolLimit(
            window: window, usedPercent: percent, used: used, allowance: allowance, extra: extra, unit: unit,
            resetsAt: resetsAt, resetSinceReading: resetSinceReading, observedAt: now.addingTimeInterval(-age)
        )
    }

    /// Codex Plus (weekly and 5-hour) by default; Pro (weekly only) with `fiveHour` nil.
    static func codex(weekly: Double = 94, fiveHour: Double? = 20, age: TimeInterval = 300, status: ToolStatus = .ok) -> ToolUsage {
        var limits = [limit(.weekly, weekly, resetsAt: codexWeeklyReset, age: age)]
        if let fiveHour { limits.append(limit(.fiveHour, fiveHour, resetsAt: now.addingTimeInterval(70 * 60), age: age)) }
        return ToolUsage(tool: .codex, limits: limits, hasFiveHourWindow: fiveHour != nil, status: status, planName: "Plus")
    }

    /// Copilot with a plan: 512 of 1,500 credits by default; `allowance` nil = "Not sure".
    static func copilot(
        used: Double = 512, allowance: Double? = 1500, extra: Double? = nil, status: ToolStatus = .ok, age: TimeInterval = 600,
        unit: UsageUnit = .aiCredits
    ) -> ToolUsage {
        let limits = [.ok, .offline, .rateLimited].contains(status) ? [limit(
            .monthly, allowance.map { used / $0 * 100 }, resetsAt: copilotReset, age: age, used: used, allowance: allowance,
            extra: extra, unit: unit
        )] : []
        return ToolUsage(tool: .copilot, limits: limits, status: status, planName: "Pro", account: "octocat")
    }

    static func toolSession(_ id: String, _ activity: SessionActivity, tool: ToolID, name: String? = nil) -> SessionInfo {
        var session = self.session("\(tool == .claude ? "" : "\(tool.rawValue):")\(id)", activity, name: name)
        session.tool = tool
        return session
    }

    /// Claude (unless `claude` is nil) plus the given tools.
    static func tools(
        claude: PlanUsage? = plan(weekly: 40, fiveHour: 10), codex: ToolUsage? = nil, copilot: ToolUsage? = nil,
        sessions: [SessionInfo] = [], issues: Set<DataIssue> = []
    ) -> HeadroomSnapshot {
        var snapshot = self.snapshot(plan: claude ?? .empty, sessions: sessions, issues: issues)
        snapshot.claudeTracked = claude != nil
        snapshot.codex = codex
        snapshot.copilot = copilot
        return snapshot
    }
}
