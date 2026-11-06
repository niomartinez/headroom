import Foundation
import HeadroomModel
import Testing
@testable import HeadroomShare

@Suite struct WidgetTimelinePlanTests {
    private let now = Date(timeIntervalSince1970: 1_790_250_000)

    private func reading(_ kind: LimitKind, _ percent: Double, resetsIn: TimeInterval?, age: TimeInterval) -> LimitReading {
        LimitReading(
            kind: kind, usedPercent: percent, resetsAt: resetsIn.map { now.addingTimeInterval($0) },
            resetIsEstimated: false, observedAt: now.addingTimeInterval(-age), source: .desktopApp
        )
    }

    private func file(
        plan: PlanUsage = .empty, codex: ToolUsage? = nil, writtenAgo: TimeInterval = 60
    ) -> WidgetSnapshotFile {
        WidgetSnapshotFile(
            writtenAt: now.addingTimeInterval(-writtenAgo), isSample: false, pillTool: .claude, showsSessionNames: true,
            snapshot: HeadroomSnapshot(
                plan: plan, sessions: [], terminalBridgeConnected: false, issues: [], generatedAt: now, codex: codex
            )
        )
    }

    private func offsets(_ dates: [Date]) -> [TimeInterval] {
        dates.map { $0.timeIntervalSince(now) }
    }

    @Test func noFileIsOneEntryAndAnHourlyReload() {
        #expect(WidgetTimelinePlan.entryDates(for: nil, now: now) == [now])
        #expect(WidgetTimelinePlan.nextReload(for: nil, now: now) == now.addingTimeInterval(3600))
    }

    /// Every 5 minutes for an hour, plus the "isn't running" moment 35 minutes after the write.
    @Test func regularEntriesEveryFiveMinutes() {
        let dates = WidgetTimelinePlan.entryDates(for: file(writtenAgo: 60), now: now)
        let expected: [TimeInterval] = Array(stride(from: 0.0, through: 3600, by: 300)) + [35 * 60 - 60]
        #expect(offsets(dates) == expected.sorted())
    }

    /// Resets and staleness within 6 hours get their own entries; later ones don't. An event next to a regular
    /// date replaces it, and nothing is closer than a minute to its neighbour.
    @Test func resetAndStaleEntries() {
        let plan = PlanUsage(
            fiveHour: reading(.fiveHour, 40, resetsIn: 10 * 60 + 20, age: 25 * 60),
            weekly: reading(.weekly, 60, resetsIn: 7 * 3600, age: 25 * 60)
        )
        let codex = ToolUsage(tool: .codex, limits: [
            ToolLimit(window: .weekly, usedPercent: 42, resetsAt: now.addingTimeInterval(2 * 3600), observedAt: now),
        ], status: .ok)
        let dates = WidgetTimelinePlan.entryDates(for: file(plan: plan, codex: codex), now: now)
        let seconds = offsets(dates)

        #expect(seconds.first == 0)
        #expect(seconds == seconds.sorted())
        #expect(zip(seconds, seconds.dropFirst()).allSatisfy { $1 - $0 >= 60 })
        #expect(seconds.contains(10 * 60 + 20))    // the 5-hour reset
        #expect(!seconds.contains(10 * 60))        // … instead of the regular 10-minute entry
        #expect(seconds.contains(5 * 60))          // Claude turns stale 30 min after the reading (25 min old)
        #expect(seconds.contains(2 * 3600))        // Codex's weekly reset
        #expect(seconds.contains(30 * 60))         // Codex turns stale after 30 min
        #expect(!seconds.contains(7 * 3600))       // past the 6-hour event horizon
    }

    @Test func eventsInThePastAreIgnored() {
        let plan = PlanUsage(weekly: reading(.weekly, 60, resetsIn: -3600, age: 3 * 3600))
        let dates = WidgetTimelinePlan.entryDates(for: file(plan: plan, writtenAgo: 2 * 3600), now: now)
        #expect(offsets(dates) == Array(stride(from: 0.0, through: 3600, by: 300)))
    }

    @Test func reloadAfterTwentyMinutesWhileFresh() {
        #expect(WidgetTimelinePlan.nextReload(for: file(writtenAgo: 60), now: now) == now.addingTimeInterval(20 * 60))
        #expect(WidgetTimelinePlan.nextReload(for: file(writtenAgo: 19 * 60), now: now) == now.addingTimeInterval(20 * 60))
        #expect(WidgetTimelinePlan.nextReload(for: file(writtenAgo: 20 * 60), now: now) == now.addingTimeInterval(3600))
    }

    @Test func runningUntilThirtyFiveMinutes() {
        #expect(file(writtenAgo: 35 * 60).isHeadroomRunning(at: now))
        #expect(!file(writtenAgo: 35 * 60 + 1).isHeadroomRunning(at: now))
    }
}
