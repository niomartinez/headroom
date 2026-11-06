import Foundation
import Testing
@testable import HeadroomModel

@Suite struct ToolLimitRolloverTests {
    private let observed = utc("2026-09-24T12:00:00Z")

    private func limit(_ window: WindowKind, _ percent: Double?, resets: String?) -> ToolLimit {
        ToolLimit(window: window, usedPercent: percent, resetsAt: resets.map(utc), observedAt: observed)
    }

    @Test func fiveHourPastResetIsNotStarted() {
        let reading = limit(.fiveHour, 64, resets: "2026-09-24T15:30:00Z")
        #expect(reading.rolledOver(now: utc("2026-09-24T15:29:59Z")) == reading)
        let rolled = reading.rolledOver(now: utc("2026-09-24T15:30:00Z"))
        #expect(rolled.usedPercent == 0)
        #expect(rolled.resetsAt == nil)
        #expect(!rolled.resetSinceReading)
        #expect(rolled.observedAt == observed)
    }

    @Test func weeklyPastResetIsResetSinceReading() {
        let reading = limit(.weekly, 94, resets: "2026-09-30T09:00:00Z")
        #expect(reading.rolledOver(now: utc("2026-09-30T08:59:00Z")) == reading)
        let rolled = reading.rolledOver(now: utc("2026-09-30T09:01:00Z"))
        #expect(rolled.usedPercent == 0)
        #expect(rolled.resetsAt == nil)
        #expect(rolled.resetSinceReading)
        #expect(rolled.window == .weekly)
    }

    @Test func dailyAndOtherWindowsAreResetSinceReading() {
        for window in [WindowKind.daily, .minutes(180)] {
            let rolled = limit(window, 50, resets: "2026-09-24T13:00:00Z").rolledOver(now: utc("2026-09-24T14:00:00Z"))
            #expect(rolled.usedPercent == 0)
            #expect(rolled.resetsAt == nil)
            #expect(rolled.resetSinceReading)
        }
    }

    @Test func unknownResetNeverRollsOver() {
        let reading = limit(.fiveHour, 40, resets: nil)
        #expect(reading.rolledOver(now: utc("2026-10-24T12:00:00Z")) == reading)
    }

    @Test func monthlyRollsToTheNextUTCMonth() {
        let reading = ToolLimit(
            window: .monthly, usedPercent: 34, used: 512, allowance: 1_500, extra: 120, unit: .aiCredits,
            resetsAt: utc("2026-10-01T00:00:00Z"), observedAt: observed
        )
        let rolled = reading.rolledOver(now: utc("2026-10-01T00:00:30Z"))
        #expect(rolled.used == 0)
        #expect(rolled.usedPercent == 0)
        #expect(rolled.extra == nil)
        #expect(rolled.allowance == 1_500)
        #expect(rolled.resetsAt == utc("2026-11-01T00:00:00Z"))
        #expect(!rolled.resetIsEstimated)
        #expect(!rolled.resetSinceReading)

        // Months later (Headroom wasn't polling): the first month start after `now`.
        #expect(reading.rolledOver(now: utc("2026-12-05T08:00:00Z")).resetsAt == utc("2027-01-01T00:00:00Z"))
    }

    /// A Codex window of about a month has no unit: its next reset is unknown, so none is invented (1.1 §2.1).
    @Test func monthlyWithoutAUnitIsResetSinceReading() throws {
        let window = try #require(WindowKind(windowMinutes: 43200))
        #expect(window == .monthly)
        let reading = limit(window, 50, resets: "2026-09-24T13:00:00Z")
        let rolled = reading.rolledOver(now: utc("2026-09-24T14:00:00Z"))
        #expect(rolled.usedPercent == 0)
        #expect(rolled.resetsAt == nil)
        #expect(rolled.resetSinceReading)
        #expect(!rolled.resetIsEstimated)
    }

    /// Sep 30 20:00 in UTC−7 is already October in UTC: GitHub's month has turned.
    @Test func monthlyBoundaryIsUTC() throws {
        let pacific = try #require(TimeZone(secondsFromGMT: -7 * 3600))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 20)))
        let reading = ToolLimit(
            window: .monthly, usedPercent: nil, used: 800, unit: .aiCredits,
            resetsAt: utc("2026-10-01T00:00:00Z"), observedAt: observed
        )
        let rolled = reading.rolledOver(now: now)
        #expect(rolled.resetsAt == utc("2026-11-01T00:00:00Z"))
        // No allowance ("Not sure"): still no percent.
        #expect(rolled.usedPercent == nil)
        #expect(rolled.used == 0)
    }

    @Test func toolUsageRollsOverEveryBucket() {
        let usage = ToolUsage(
            tool: .codex,
            limits: [limit(.weekly, 94, resets: "2026-09-30T09:00:00Z"), limit(.fiveHour, 20, resets: "2026-09-24T13:00:00Z")],
            hasFiveHourWindow: true,
            otherBuckets: [NamedLimits(id: "spark", name: "Spark", limits: [limit(.fiveHour, 80, resets: "2026-09-24T13:00:00Z")])],
            status: .ok
        )
        let rolled = usage.rolledOver(now: utc("2026-09-24T14:00:00Z"))
        #expect(rolled.limits.map(\.usedPercent) == [94, 0])
        #expect(rolled.otherBuckets[0].limits[0].usedPercent == 0)
        #expect(rolled.status == .ok)
    }
}

/// `LimitReading.rolledOver(now:)` moved from `PlanUsageResolver` unchanged (spec §3.1); the resolver's tests still
/// cover it through `resolve`.
@Suite struct LimitReadingRolloverTests {
    private func reading(_ kind: LimitKind, _ used: Double, resets: String?, estimated: Bool = false) -> LimitReading {
        LimitReading(
            kind: kind, usedPercent: used, resetsAt: resets.map(utc), resetIsEstimated: estimated,
            observedAt: utc("2026-09-24T12:00:00Z"), source: .terminal
        )
    }

    @Test func fiveHourPastResetIsNotStarted() {
        let rolled = reading(.fiveHour, 20, resets: "2026-09-24T15:30:00Z").rolledOver(now: utc("2026-09-24T15:30:00Z"))
        #expect(rolled.usedPercent == 0)
        #expect(rolled.resetsAt == nil)
    }

    @Test func weeklyPastResetMovesToTheNextRepeat() {
        let original = reading(.weekly, 88, resets: "2026-09-27T11:00:00Z", estimated: true)
        #expect(original.rolledOver(now: utc("2026-09-27T10:59:59Z")) == original)
        let rolled = original.rolledOver(now: utc("2026-10-12T09:00:00Z"))
        #expect(rolled.usedPercent == 0)
        #expect(rolled.resetsAt == utc("2026-10-18T11:00:00Z"))
        #expect(rolled.resetIsEstimated)
    }

    @Test func unknownResetZeroesAfterAWholeWindow() {
        let fiveHour = reading(.fiveHour, 40, resets: nil)
        #expect(fiveHour.rolledOver(now: utc("2026-09-24T16:59:59Z")).usedPercent == 40)
        #expect(fiveHour.rolledOver(now: utc("2026-09-24T17:00:00Z")).usedPercent == 0)
        let weekly = reading(.weekly, 88, resets: nil)
        #expect(weekly.rolledOver(now: utc("2026-10-01T11:59:59Z")).usedPercent == 88)
        #expect(weekly.rolledOver(now: utc("2026-10-01T12:00:00Z")).usedPercent == 0)
    }

    @Test func planUsageRollsBothAndKeepsExtra() {
        let plan = PlanUsage(
            fiveHour: reading(.fiveHour, 20, resets: "2026-09-24T15:30:00Z"),
            weekly: reading(.weekly, 88, resets: "2026-09-27T11:00:00Z"),
            extraUsagePercent: 12
        )
        let rolled = plan.rolledOver(now: utc("2026-09-24T16:00:00Z"))
        #expect(rolled.fiveHour?.usedPercent == 0)
        #expect(rolled.weekly?.usedPercent == 88)
        #expect(rolled.extraUsagePercent == 12)
    }
}
