import Foundation
import HeadroomModel
import Testing
@testable import UsageKit

@Suite struct PlanUsageResolverTests {
    private func reading(
        _ kind: LimitKind, _ used: Double, resets: String?, at observed: String, _ source: ReadingSource
    ) -> LimitReading {
        LimitReading(
            kind: kind, usedPercent: used, resetsAt: resets.map(utc),
            resetIsEstimated: source == .desktopApp, observedAt: utc(observed), source: source
        )
    }

    /// Terminal reading at 12:00: 5-hour 20 % until 15:30, weekly 88 % until Sunday 11:00.
    private var terminal: PlanUsage {
        PlanUsage(
            fiveHour: reading(.fiveHour, 20, resets: "2026-09-24T15:30:00Z", at: "2026-09-24T12:00:00Z", .terminal),
            weekly: reading(.weekly, 88, resets: "2026-09-27T11:00:00Z", at: "2026-09-24T12:00:00Z", .terminal)
        )
    }

    /// Desktop reading at `observed` with its own (inferred) reset guesses.
    private func desktop(fh: Double, sd: Double, at observed: String, xu: Double? = nil) -> PlanUsage {
        PlanUsage(
            fiveHour: reading(.fiveHour, fh, resets: "2026-09-24T15:20:00Z", at: observed, .desktopApp),
            weekly: reading(.weekly, sd, resets: "2026-09-29T19:00:00Z", at: observed, .desktopApp),
            extraUsagePercent: xu
        )
    }

    private func resolve(
        desktop: PlanUsage?, samples: [DesktopUsageSample] = [], terminal: PlanUsage?, now: String
    ) -> PlanUsage {
        PlanUsageResolver.resolve(desktop: desktop, desktopSamples: samples, terminal: terminal, now: utc(now))
    }

    @Test func bothMissingIsEmpty() {
        #expect(resolve(desktop: nil, terminal: nil, now: "2026-09-24T12:00:00Z") == .empty)
    }

    @Test func newerTerminalWins() {
        let result = resolve(desktop: desktop(fh: 18, sd: 87, at: "2026-09-24T11:45:00Z"), terminal: terminal, now: "2026-09-24T12:05:00Z")
        #expect(result.fiveHour == terminal.fiveHour)
        #expect(result.weekly == terminal.weekly)
    }

    @Test func equalObservationTimesPreferTheExactTerminalReading() {
        let result = resolve(desktop: desktop(fh: 18, sd: 87, at: "2026-09-24T12:00:00Z"), terminal: terminal, now: "2026-09-24T12:05:00Z")
        #expect(result.fiveHour?.source == .terminal)
        #expect(result.weekly?.source == .terminal)
    }

    @Test func newerDesktopWinsAndBorrowsTheTerminalsExactResets() throws {
        let samples = [
            sample("2026-09-24T11:45:00Z", fh: 19, sd: 88),
            sample("2026-09-24T12:15:00Z", fh: 22, sd: 89),
        ]
        let result = resolve(
            desktop: desktop(fh: 22, sd: 89, at: "2026-09-24T12:15:00Z"), samples: samples,
            terminal: terminal, now: "2026-09-24T12:20:00Z"
        )
        let fiveHour = try #require(result.fiveHour)
        #expect(fiveHour.usedPercent == 22)
        #expect(fiveHour.source == .desktopApp)
        #expect(fiveHour.observedAt == utc("2026-09-24T12:15:00Z"))
        #expect(fiveHour.resetsAt == utc("2026-09-24T15:30:00Z"))
        #expect(fiveHour.resetIsEstimated == false)

        let weekly = try #require(result.weekly)
        #expect(weekly.usedPercent == 89)
        #expect(weekly.resetsAt == utc("2026-09-27T11:00:00Z"))
        #expect(weekly.resetIsEstimated == false)
    }

    @Test func eachKindPicksItsOwnWinner() {
        let fiveHourOnly = PlanUsage(fiveHour: terminal.fiveHour)
        let result = resolve(desktop: desktop(fh: 18, sd: 87, at: "2026-09-24T11:45:00Z"), terminal: fiveHourOnly, now: "2026-09-24T12:05:00Z")
        #expect(result.fiveHour?.source == .terminal)
        #expect(result.weekly?.source == .desktopApp)
        #expect(result.weekly?.usedPercent == 87)
    }

    @Test func terminalResetThatPassedBeforeTheDesktopReadingIsNotBorrowed() {
        let old = PlanUsage(
            fiveHour: reading(.fiveHour, 20, resets: "2026-09-24T12:10:00Z", at: "2026-09-24T12:00:00Z", .terminal),
            weekly: reading(.weekly, 88, resets: "2026-09-24T12:10:00Z", at: "2026-09-24T12:00:00Z", .terminal)
        )
        let result = resolve(desktop: desktop(fh: 2, sd: 1, at: "2026-09-24T12:15:00Z"), terminal: old, now: "2026-09-24T12:20:00Z")
        #expect(result.fiveHour?.resetsAt == utc("2026-09-24T15:20:00Z"))
        #expect(result.fiveHour?.resetIsEstimated == true)
        #expect(result.weekly?.resetsAt == utc("2026-09-29T19:00:00Z"))
        #expect(result.weekly?.resetIsEstimated == true)
    }

    @Test func resetSeenInDesktopSamplesAfterTheTerminalReadingBlocksBorrowing() {
        // A one-off weekly reset between the terminal reading (12:00) and the desktop reading.
        let samples = [
            sample("2026-09-24T11:45:00Z", fh: 19, sd: 88),
            sample("2026-09-24T12:30:00Z", fh: 25, sd: 89),
            sample("2026-09-24T12:45:00Z", fh: 3, sd: 2),
            sample("2026-09-24T13:00:00Z", fh: 5, sd: 3),
        ]
        let result = resolve(
            desktop: desktop(fh: 5, sd: 3, at: "2026-09-24T13:00:00Z"), samples: samples,
            terminal: terminal, now: "2026-09-24T13:05:00Z"
        )
        #expect(result.fiveHour?.resetsAt == utc("2026-09-24T15:20:00Z"))
        #expect(result.fiveHour?.resetIsEstimated == true)
        #expect(result.weekly?.resetsAt == utc("2026-09-29T19:00:00Z"))
        #expect(result.weekly?.resetIsEstimated == true)
    }

    @Test func dropFromTheTerminalValueToTheNextDesktopSampleCountsAsAReset() {
        let samples = [sample("2026-09-24T12:15:00Z", fh: 2, sd: 89)]
        let result = resolve(
            desktop: desktop(fh: 2, sd: 89, at: "2026-09-24T12:15:00Z"), samples: samples,
            terminal: terminal, now: "2026-09-24T12:20:00Z"
        )
        #expect(result.fiveHour?.resetIsEstimated == true)
        #expect(result.fiveHour?.resetsAt == utc("2026-09-24T15:20:00Z"))
        #expect(result.weekly?.resetIsEstimated == false)
        #expect(result.weekly?.resetsAt == utc("2026-09-27T11:00:00Z"))
    }

    @Test func smallWeeklyDipIsNotAReset() {
        let samples = [sample("2026-09-24T12:15:00Z", fh: 21, sd: 80)]
        let result = resolve(
            desktop: desktop(fh: 21, sd: 80, at: "2026-09-24T12:15:00Z"), samples: samples,
            terminal: terminal, now: "2026-09-24T12:20:00Z"
        )
        #expect(result.weekly?.resetsAt == utc("2026-09-27T11:00:00Z"))
        #expect(result.weekly?.resetIsEstimated == false)
    }

    // MARK: Account switches (the terminal reading carries no org)

    @Test func anotherAccountsSampleNearTheTerminalReadingBlocksBorrowing() {
        // The desktop app was on org-b around the terminal reading (12:00), so nothing says the terminal's windows
        // are org-a's.
        let samples = [
            sample("2026-09-24T12:05:00Z", org: "org-b", fh: 0, sd: 0),
            sample("2026-09-24T12:15:00Z", org: "org-a", fh: 22, sd: 89),
        ]
        let result = resolve(
            desktop: desktop(fh: 22, sd: 89, at: "2026-09-24T12:15:00Z"), samples: samples,
            terminal: terminal, now: "2026-09-24T12:20:00Z"
        )
        #expect(result.fiveHour?.resetsAt == utc("2026-09-24T15:20:00Z"))
        #expect(result.fiveHour?.resetIsEstimated == true)
        #expect(result.weekly?.resetsAt == utc("2026-09-29T19:00:00Z"))
        #expect(result.weekly?.resetIsEstimated == true)
    }

    @Test func switchAwayAndBackSinceTheTerminalReadingBlocksBorrowing() {
        let samples = [
            sample("2026-09-24T11:45:00Z", org: "org-a", fh: 19, sd: 88),
            sample("2026-09-24T12:05:00Z", org: "org-b", fh: 0, sd: 0),
            sample("2026-09-24T12:15:00Z", org: "org-a", fh: 22, sd: 89),
        ]
        let result = resolve(
            desktop: desktop(fh: 22, sd: 89, at: "2026-09-24T12:15:00Z"), samples: samples,
            terminal: terminal, now: "2026-09-24T12:20:00Z"
        )
        #expect(result.fiveHour?.resetIsEstimated == true)
        #expect(result.weekly?.resetIsEstimated == true)
    }

    @Test func switchesBeforeTheTerminalReadingDoNotMatter() {
        let samples = [
            sample("2026-09-24T10:00:00Z", org: "org-a", fh: 90, sd: 70),
            sample("2026-09-24T11:00:00Z", org: "org-b", fh: 0, sd: 0),
            sample("2026-09-24T11:45:00Z", org: "org-a", fh: 19, sd: 88),
            sample("2026-09-24T12:15:00Z", org: "org-a", fh: 22, sd: 89),
        ]
        let result = resolve(
            desktop: desktop(fh: 22, sd: 89, at: "2026-09-24T12:15:00Z"), samples: samples,
            terminal: terminal, now: "2026-09-24T12:20:00Z"
        )
        #expect(result.fiveHour?.resetsAt == utc("2026-09-24T15:30:00Z"))
        #expect(result.fiveHour?.resetIsEstimated == false)
        #expect(result.weekly?.resetsAt == utc("2026-09-27T11:00:00Z"))
        #expect(result.weekly?.resetIsEstimated == false)
    }

    @Test func withoutSamplesNothingShowsTheAccountSoNothingIsBorrowed() {
        let result = resolve(desktop: desktop(fh: 22, sd: 89, at: "2026-09-24T12:15:00Z"), terminal: terminal, now: "2026-09-24T12:20:00Z")
        #expect(result.fiveHour?.resetIsEstimated == true)
        #expect(result.weekly?.resetIsEstimated == true)
    }

    @Test func terminalReadingFromBeforeADesktopAccountSwitchLendsNoResets() throws {
        // The desktop app switched to abc4 at 15:28:00; the terminal reported the first account's limits at 15:27:30.
        let samples = [
            sample("2026-09-24T15:21:21Z", org: "b83b", fh: 71, sd: 100),
            sample("2026-09-24T15:27:02Z", org: "b83b", fh: 71, sd: 100),
            sample("2026-09-24T15:28:00Z", org: "abc4", fh: 40, sd: 50),
        ]
        let other = PlanUsage(
            fiveHour: reading(.fiveHour, 20, resets: "2026-09-24T17:00:00Z", at: "2026-09-24T15:27:30Z", .terminal),
            weekly: reading(.weekly, 10, resets: "2026-09-29T08:00:00Z", at: "2026-09-24T15:27:30Z", .terminal)
        )
        let now = utc("2026-09-24T15:29:00Z")
        let result = PlanUsageResolver.resolve(
            desktop: DesktopUsageAnalyzer.currentUsage(samples: samples, now: now), desktopSamples: samples,
            terminal: other, now: now
        )
        let fiveHour = try #require(result.fiveHour)
        #expect(fiveHour.usedPercent == 40)
        #expect(fiveHour.resetIsEstimated == true)
        #expect(fiveHour.resetsAt == utc("2026-09-24T20:28:00Z"))
        let weekly = try #require(result.weekly)
        #expect(weekly.usedPercent == 50)
        #expect(weekly.resetIsEstimated == true)
        #expect(weekly.resetsAt == nil)
    }

    /// The real 2026-09-21 20:47:44 switch from b83b (capped at 5-hour 100 %, weekly 61 %) to abc4 (weekly 95 %).
    private let realSwitch = [
        sample("2026-09-21T20:04:27Z", org: "b83b", fh: 79, sd: 58),
        sample("2026-09-21T20:19:27Z", org: "b83b", fh: 87, sd: 59),
        sample("2026-09-21T20:34:27Z", org: "b83b", fh: 100, sd: 61),
        sample("2026-09-21T20:47:44Z", org: "abc4", fh: 4, sd: 95),
        sample("2026-09-21T21:34:27Z", org: "abc4", fh: 36, sd: 99),
        sample("2026-09-21T21:45:54Z", org: "abc4", fh: 45, sd: 100),
    ]

    /// The terminal's b83b reading at `observed`.
    private func b83bTerminal(at observed: String) -> PlanUsage {
        PlanUsage(
            fiveHour: reading(.fiveHour, 100, resets: "2026-09-21T22:00:00Z", at: observed, .terminal),
            weekly: reading(.weekly, 61, resets: "2026-09-27T11:00:00Z", at: observed, .terminal)
        )
    }

    private func resolveRealSwitch(terminalAt observed: String, now: String) -> PlanUsage {
        let samples = realSwitch.filter { $0.time <= utc(now) }
        return PlanUsageResolver.resolve(
            desktop: DesktopUsageAnalyzer.currentUsage(samples: samples, now: utc(now)), desktopSamples: samples,
            terminal: b83bTerminal(at: observed), now: utc(now)
        )
    }

    @Test(arguments: ["2026-09-21T20:50:00Z", "2026-09-21T21:50:00Z"])
    func realSwitchKeepsTheOtherAccountsWeeklyResetOut(now: String) throws {
        let result = resolveRealSwitch(terminalAt: "2026-09-21T20:40:00Z", now: now)
        let weekly = try #require(result.weekly)
        #expect(weekly.source == .desktopApp)
        #expect(weekly.resetIsEstimated == true)
        #expect(weekly.resetsAt != utc("2026-09-27T11:00:00Z"))
        #expect(result.fiveHour?.resetIsEstimated == true)
    }

    @Test func terminalStillOnTheOldAccountAfterTheSwitchLendsNoResets() throws {
        // The terminal CLI has its own login: at 20:50 it still reports b83b, after the desktop app moved to abc4.
        // abc4's 95 % at 20:47:44 is in that weekly window, so 61 % can't be abc4's.
        let result = resolveRealSwitch(terminalAt: "2026-09-21T20:50:00Z", now: "2026-09-21T21:40:00Z")
        let weekly = try #require(result.weekly)
        #expect(weekly.usedPercent == 99)
        #expect(weekly.resetIsEstimated == true)
        #expect(weekly.resetsAt != utc("2026-09-27T11:00:00Z"))
        #expect(result.fiveHour?.resetIsEstimated == true)
    }

    @Test func sameWindowSampleAboveTheTerminalValueBlocksBorrowing() {
        // Usage never falls inside a window: 60 % → 20 % (5-hour, window 10:30–15:30) and 99 % → 88 % (weekly) mean
        // the terminal reading is not this account's.
        let samples = [
            sample("2026-09-24T11:45:00Z", fh: 60, sd: 99),
            sample("2026-09-24T12:15:00Z", fh: 62, sd: 99),
        ]
        let result = resolve(
            desktop: desktop(fh: 62, sd: 99, at: "2026-09-24T12:15:00Z"), samples: samples,
            terminal: terminal, now: "2026-09-24T12:20:00Z"
        )
        #expect(result.fiveHour?.resetsAt == utc("2026-09-24T15:20:00Z"))
        #expect(result.fiveHour?.resetIsEstimated == true)
        #expect(result.weekly?.resetsAt == utc("2026-09-29T19:00:00Z"))
        #expect(result.weekly?.resetIsEstimated == true)
    }

    @Test func aResetBetweenTheEarlierSampleAndTheTerminalReadingStillLendsIt() {
        // 60 % at 11:50 was the previous five-hour window; the terminal's window began at 12:05.
        let samples = [
            sample("2026-09-24T11:50:00Z", fh: 60, sd: 88),
            sample("2026-09-24T12:15:00Z", fh: 3, sd: 89),
        ]
        let fresh = PlanUsage(
            fiveHour: reading(.fiveHour, 2, resets: "2026-09-24T17:05:00Z", at: "2026-09-24T12:05:00Z", .terminal),
            weekly: reading(.weekly, 88, resets: "2026-09-27T11:00:00Z", at: "2026-09-24T12:05:00Z", .terminal)
        )
        let result = resolve(
            desktop: desktop(fh: 3, sd: 89, at: "2026-09-24T12:15:00Z"), samples: samples,
            terminal: fresh, now: "2026-09-24T12:20:00Z"
        )
        #expect(result.fiveHour?.resetsAt == utc("2026-09-24T17:05:00Z"))
        #expect(result.fiveHour?.resetIsEstimated == false)
        #expect(result.weekly?.resetsAt == utc("2026-09-27T11:00:00Z"))
        #expect(result.weekly?.resetIsEstimated == false)
    }

    @Test func passedFiveHourResetMeansNotStarted() throws {
        let result = resolve(desktop: nil, terminal: terminal, now: "2026-09-24T15:30:00Z")
        let fiveHour = try #require(result.fiveHour)
        #expect(fiveHour.usedPercent == 0)
        #expect(fiveHour.resetsAt == nil)
        #expect(fiveHour.observedAt == utc("2026-09-24T12:00:00Z"))
        #expect(result.weekly == terminal.weekly)
    }

    @Test func passedWeeklyResetMovesAWeekAheadAndKeepsItsFlag() throws {
        let exact = try #require(resolve(desktop: nil, terminal: terminal, now: "2026-09-27T12:00:00Z").weekly)
        #expect(exact.usedPercent == 0)
        #expect(exact.resetsAt == utc("2026-10-04T11:00:00Z"))
        #expect(exact.resetIsEstimated == false)

        let inferred = try #require(resolve(desktop: desktop(fh: 1, sd: 50, at: "2026-09-24T12:00:00Z"), terminal: nil, now: "2026-09-29T19:00:00Z").weekly)
        #expect(inferred.usedPercent == 0)
        #expect(inferred.resetsAt == utc("2026-10-06T19:00:00Z"))
        #expect(inferred.resetIsEstimated == true)
    }

    @Test func weeklyRolloverSkipsWholeWeeksThatAlsoPassed() {
        let result = resolve(desktop: nil, terminal: terminal, now: "2026-10-12T09:00:00Z")
        #expect(result.weekly?.resetsAt == utc("2026-10-18T11:00:00Z"))
        #expect(result.weekly?.usedPercent == 0)
    }

    @Test func borrowedResetThatHasSincePassedRollsOver() {
        // The desktop reading (15:20) was taken inside the terminal's window, which ended at 15:30.
        let samples = [sample("2026-09-24T15:20:00Z", fh: 60, sd: 90)]
        let result = resolve(
            desktop: desktop(fh: 60, sd: 90, at: "2026-09-24T15:20:00Z"), samples: samples,
            terminal: terminal, now: "2026-09-24T15:40:00Z"
        )
        #expect(result.fiveHour?.usedPercent == 0)
        #expect(result.fiveHour?.resetsAt == nil)
        #expect(result.weekly?.usedPercent == 90)
    }

    @Test func fiveHourReadingOlderThanAWindowWithUnknownResetIsZero() {
        // Inference found no reset time (the run spans more than 5 h), then the desktop app stopped sampling.
        // Whatever window 40 % belonged to has ended by now.
        var stale = desktop(fh: 40, sd: 50, at: "2026-09-24T10:00:00Z")
        stale.fiveHour?.resetsAt = nil
        let justUnder = resolve(desktop: stale, terminal: nil, now: "2026-09-24T14:59:59Z")
        #expect(justUnder.fiveHour?.usedPercent == 40)
        let later = resolve(desktop: stale, terminal: nil, now: "2026-09-24T15:00:00Z")
        #expect(later.fiveHour?.usedPercent == 0)
        #expect(later.fiveHour?.resetsAt == nil)
        #expect(later.fiveHour?.observedAt == utc("2026-09-24T10:00:00Z"))
    }

    @Test func weeklyReadingOlderThanAWeekWithUnknownResetIsZero() {
        let noReset = PlanUsage(weekly: reading(.weekly, 88, resets: nil, at: "2026-09-24T12:00:00Z", .terminal))
        #expect(resolve(desktop: nil, terminal: noReset, now: "2026-10-01T11:59:59Z").weekly?.usedPercent == 88)
        let later = resolve(desktop: nil, terminal: noReset, now: "2026-10-01T12:00:00Z")
        #expect(later.weekly?.usedPercent == 0)
        #expect(later.weekly?.resetsAt == nil)
    }

    @Test func desktopOnlyIsPassedThroughWithExtraUsage() {
        let only = desktop(fh: 18, sd: 87, at: "2026-09-24T11:45:00Z", xu: 12)
        #expect(resolve(desktop: only, terminal: nil, now: "2026-09-24T12:00:00Z") == only)
    }

    @Test func extraUsageComesFromTheDesktopEvenWhenTheTerminalWins() {
        let result = resolve(desktop: desktop(fh: 18, sd: 87, at: "2026-09-24T11:45:00Z", xu: 12), terminal: terminal, now: "2026-09-24T12:05:00Z")
        #expect(result.fiveHour?.source == .terminal)
        #expect(result.extraUsagePercent == 12)
        #expect(resolve(desktop: nil, terminal: terminal, now: "2026-09-24T12:05:00Z").extraUsagePercent == nil)
    }
}
