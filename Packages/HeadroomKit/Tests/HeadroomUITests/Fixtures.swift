import Foundation
import HeadroomModel
@testable import HeadroomUI

/// Synthetic data only: no real session names, paths or ids.
enum Fixture {
    static let manila = TimeZone(identifier: "Asia/Manila")!
    static let posix = Locale(identifier: "en_US_POSIX")

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = manila
        calendar.locale = posix
        return calendar
    }

    static let format = HeadroomFormat(calendar: calendar, timeZone: manila, locale: posix)

    /// Thursday 2026-09-24 14:10 in Manila.
    static let now = date(2026, 9, 24, 14, 10)

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    static func reading(
        _ kind: LimitKind,
        _ percent: Double,
        resetsAt: Date? = nil,
        estimated: Bool = false,
        age: TimeInterval = 120,
        source: ReadingSource = .desktopApp
    ) -> LimitReading {
        LimitReading(
            kind: kind,
            usedPercent: percent,
            resetsAt: resetsAt,
            resetIsEstimated: estimated,
            observedAt: now.addingTimeInterval(-age),
            source: source
        )
    }

    static func plan(weekly: Double?, fiveHour: Double?, age: TimeInterval = 120, extra: Double? = nil) -> PlanUsage {
        PlanUsage(
            fiveHour: fiveHour.map { reading(.fiveHour, $0, age: age) },
            weekly: weekly.map { reading(.weekly, $0, age: age) },
            extraUsagePercent: extra
        )
    }

    static func context(_ used: Int, of window: Int, model: String? = "test-model-large", assumed: Bool = false) -> ContextUsage {
        ContextUsage(usedTokens: used, windowTokens: window, model: model, windowIsExact: false, observedAt: nil, windowIsAssumed: assumed)
    }

    static func session(
        _ id: String,
        _ activity: SessionActivity,
        name: String? = nil,
        path: String? = nil,
        origin: SessionOrigin = .desktop,
        context: ContextUsage? = nil
    ) -> SessionInfo {
        SessionInfo(
            id: id,
            name: name ?? "Session \(id)",
            projectPath: path,
            origin: origin,
            activity: activity,
            activitySince: nil,
            startedAt: nil,
            pid: nil,
            transcriptPath: nil,
            context: context
        )
    }

    static func snapshot(
        plan: PlanUsage = plan(weekly: 40, fiveHour: 10),
        sessions: [SessionInfo] = [],
        issues: Set<DataIssue> = [],
        connected: Bool = false
    ) -> HeadroomSnapshot {
        HeadroomSnapshot(plan: plan, sessions: sessions, terminalBridgeConnected: connected, issues: issues, generatedAt: now)
    }
}
