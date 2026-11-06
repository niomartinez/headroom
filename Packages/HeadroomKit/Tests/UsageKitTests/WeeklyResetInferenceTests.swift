import Foundation
import Testing
@testable import UsageKit

@Suite struct WeeklyResetInferenceTests {
    private func infer(_ samples: [DesktopUsageSample], now: String) -> Date? {
        DesktopUsageAnalyzer.inferWeeklyReset(samples: samples, now: utc(now))
    }

    @Test func dropBetweenSamplesRoundsUpToTheNextFullHour() {
        let samples = [sample("2026-09-20T10:52:00Z", sd: 90), sample("2026-09-20T11:07:00Z", sd: 3)]
        #expect(infer(samples, now: "2026-09-20T11:10:00Z") == utc("2026-09-27T11:00:00Z"))
    }

    @Test func eventIsClampedToTheSampleThatShowsTheDrop() {
        let samples = [sample("2026-09-20T10:40:00Z", sd: 90), sample("2026-09-20T10:55:00Z", sd: 3)]
        #expect(infer(samples, now: "2026-09-20T11:10:00Z") == utc("2026-09-27T10:55:00Z"))
    }

    @Test func sampleExactlyOnTheHourIsNotRoundedFurther() {
        let samples = [sample("2026-09-20T11:00:00Z", sd: 90), sample("2026-09-20T11:15:00Z", sd: 3)]
        #expect(infer(samples, now: "2026-09-20T11:20:00Z") == utc("2026-09-27T11:00:00Z"))
    }

    @Test func nextResetIsTheFirstWeeklyRepeatStrictlyAfterNow() {
        let samples = [sample("2026-09-06T10:52:00Z", sd: 90), sample("2026-09-06T11:07:00Z", sd: 3)]
        #expect(infer(samples, now: "2026-09-24T12:00:00Z") == utc("2026-09-27T11:00:00Z"))
        #expect(infer(samples, now: "2026-09-20T11:00:00Z") == utc("2026-09-27T11:00:00Z"))
        #expect(infer(samples, now: "2026-09-20T10:59:59Z") == utc("2026-09-20T11:00:00Z"))
    }

    @Test func noDropGivesNil() {
        let samples = [sample("2026-09-20T10:00:00Z", sd: 10), sample("2026-09-21T10:00:00Z", sd: 30), sample("2026-09-22T10:00:00Z", sd: 30)]
        #expect(infer(samples, now: "2026-09-22T11:00:00Z") == nil)
        #expect(infer([], now: "2026-09-22T11:00:00Z") == nil)
        #expect(infer([sample("2026-09-22T10:00:00Z", sd: 5)], now: "2026-09-22T11:00:00Z") == nil)
    }

    @Test func dropsSmallerThanTenPointsAreIgnored() {
        let nine = [sample("2026-09-20T10:52:00Z", sd: 50), sample("2026-09-20T11:07:00Z", sd: 41)]
        #expect(infer(nine, now: "2026-09-20T12:00:00Z") == nil)

        let ten = [sample("2026-09-20T10:52:00Z", sd: 50), sample("2026-09-20T11:07:00Z", sd: 40)]
        #expect(infer(ten, now: "2026-09-20T12:00:00Z") == utc("2026-09-27T11:00:00Z"))
    }

    @Test func severalWeeksOnOneScheduleUseTheNewestEvent() {
        let samples = [
            sample("2026-09-06T10:52:00Z", sd: 70), sample("2026-09-06T11:07:00Z", sd: 0),
            sample("2026-09-13T10:52:00Z", sd: 80), sample("2026-09-13T11:07:00Z", sd: 1),
            sample("2026-09-20T10:40:00Z", sd: 90), sample("2026-09-20T10:55:00Z", sd: 2),
            sample("2026-09-22T09:00:00Z", sd: 30),
        ]
        #expect(infer(samples, now: "2026-09-22T09:05:00Z") == utc("2026-09-27T10:55:00Z"))
    }

    @Test func movedScheduleFollowsTheNewestEvent() {
        let samples = [
            sample("2026-09-06T10:52:00Z", sd: 70), sample("2026-09-06T11:07:00Z", sd: 0),
            sample("2026-09-15T14:40:00Z", sd: 80), sample("2026-09-15T14:55:00Z", sd: 1),
            sample("2026-09-22T09:00:00Z", sd: 30),
        ]
        #expect(infer(samples, now: "2026-09-24T12:00:00Z") == utc("2026-09-29T14:55:00Z"))
    }

    @Test func offScheduleResetDoesNotMoveAScheduleThatOlderEventsAgreeOn() {
        // Mirrors the developer's real history: a clean Sunday 11:00 reset, a Sunday reset hidden in a
        // two-day sampling gap, then a one-off mid-week reset. The terminal reported Sunday 11:00 afterwards.
        let samples = [
            sample("2026-09-06T10:54:00Z", sd: 69), sample("2026-09-06T11:09:00Z", sd: 0),
            sample("2026-09-11T18:02:00Z", sd: 74), sample("2026-09-13T18:12:00Z", sd: 0),
            sample("2026-09-15T18:31:00Z", sd: 88), sample("2026-09-15T18:46:00Z", sd: 2),
            sample("2026-09-17T13:06:00Z", sd: 40),
        ]
        #expect(infer(samples, now: "2026-09-17T13:10:00Z") == utc("2026-09-20T11:00:00Z"))
    }

    @Test func estimateThatFitsEveryEventBeatsANewerOneThatDoesNot() {
        // Week 1 says (10:40, 10:55], week 2 says (10:52, 11:07]: only 10:55 fits both.
        let samples = [
            sample("2026-09-13T10:40:00Z", sd: 80), sample("2026-09-13T10:55:00Z", sd: 1),
            sample("2026-09-20T10:52:00Z", sd: 90), sample("2026-09-20T11:07:00Z", sd: 2),
        ]
        #expect(infer(samples, now: "2026-09-21T00:00:00Z") == utc("2026-09-27T10:55:00Z"))
    }

    @Test func scheduleThatMissedAResetGivesWayToTheNewOne() {
        // Four Sunday 11:00 resets, then the schedule moves to Tuesday 14:55. The next Sunday passes with weekly
        // usage flat around 40 %, sampled on both sides of 11:00, so Sunday can no longer be the schedule even
        // though it has more supporting events.
        let sundays = ["2026-08-30", "2026-09-06", "2026-09-13", "2026-09-20"].flatMap { day in
            [sample("\(day)T10:52:00Z", sd: 70), sample("\(day)T11:07:00Z", sd: 2)]
        }
        let samples = sundays + [
            sample("2026-09-22T14:40:00Z", sd: 50), sample("2026-09-22T14:55:00Z", sd: 1),
            sample("2026-09-27T10:52:00Z", sd: 40), sample("2026-09-27T11:07:00Z", sd: 41),
        ]
        #expect(infer(samples, now: "2026-09-27T11:10:00Z") == utc("2026-09-29T14:55:00Z"))
    }

    @Test func missedRepeatOfTheOnlyScheduleGivesNil() {
        // The only event came from a two-day sampling gap, so its estimate (Friday 18:00) is a guess. A week later
        // Friday 18:00 passes with usage at 60 %: that schedule is wrong, and there is no other.
        let samples = [
            sample("2026-09-11T17:10:00Z", sd: 70), sample("2026-09-13T18:12:00Z", sd: 0),
            sample("2026-09-18T17:52:00Z", sd: 60), sample("2026-09-18T18:07:00Z", sd: 60),
        ]
        #expect(infer(samples, now: "2026-09-18T18:10:00Z") == nil)
    }

    @Test func dropSeenOneSampleLateDoesNotRefuteTheSchedule() {
        // A sample just after 11:00 still shows the old value (clock skew or a late fetch); the drop shows in the
        // next one. The Sunday 11:00 schedule stands.
        let samples = [
            sample("2026-09-06T10:52:00Z", sd: 70), sample("2026-09-06T11:07:00Z", sd: 2),
            sample("2026-09-13T10:52:00Z", sd: 80), sample("2026-09-13T11:07:00Z", sd: 1),
            sample("2026-09-20T10:52:00Z", sd: 61), sample("2026-09-20T11:03:00Z", sd: 62),
            sample("2026-09-20T11:18:00Z", sd: 1),
        ]
        #expect(infer(samples, now: "2026-09-20T11:20:00Z") == utc("2026-09-27T11:00:00Z"))
    }

    @Test func lowUsageAcrossARepeatDoesNotRefuteTheSchedule() {
        // Below 30 % heavy use right after a reset could hide its 10-point drop, so flat low usage proves nothing.
        let samples = [
            sample("2026-09-06T10:52:00Z", sd: 70), sample("2026-09-06T11:07:00Z", sd: 2),
            sample("2026-09-13T10:52:00Z", sd: 25), sample("2026-09-13T11:07:00Z", sd: 26),
            sample("2026-09-14T09:00:00Z", sd: 30),
        ]
        #expect(infer(samples, now: "2026-09-14T09:05:00Z") == utc("2026-09-20T11:00:00Z"))
    }

    @Test func wideSamplingGapAcrossARepeatDoesNotRefuteTheSchedule() {
        // Samples an hour apart around 11:00 could hide a reset followed by heavy use.
        let samples = [
            sample("2026-09-06T10:52:00Z", sd: 70), sample("2026-09-06T11:07:00Z", sd: 2),
            sample("2026-09-13T10:30:00Z", sd: 50), sample("2026-09-13T11:31:00Z", sd: 45),
        ]
        #expect(infer(samples, now: "2026-09-13T11:35:00Z") == utc("2026-09-20T11:00:00Z"))
    }

    @Test func onlyTheNewestOrgCounts() {
        let samples = [
            sample("2026-09-20T10:52:00Z", org: "org-b", sd: 90), sample("2026-09-20T11:07:00Z", org: "org-b", sd: 3),
            sample("2026-09-21T10:52:00Z", org: "org-a", sd: 90), sample("2026-09-21T11:07:00Z", org: "org-a", sd: 3),
            sample("2026-09-22T10:00:00Z", org: "org-a", sd: 20),
        ]
        #expect(infer(samples, now: "2026-09-22T10:05:00Z") == utc("2026-09-28T11:00:00Z"))
    }

    @Test func samplesWithoutWeeklyValueAreSkipped() {
        let samples = [
            sample("2026-09-20T10:52:00Z", fh: 5, sd: 90),
            sample("2026-09-20T11:00:00Z", fh: 6, sd: nil),
            sample("2026-09-20T11:07:00Z", fh: 7, sd: 3),
        ]
        #expect(infer(samples, now: "2026-09-20T11:10:00Z") == utc("2026-09-27T11:00:00Z"))
    }

    @Test func onlyTheNewestEventsAreWeighed() {
        // Many old events on one schedule must not outvote the newest year of history; this also bounds
        // the work on hostile input (the vote is quadratic in the number of events).
        let old = (0..<(2 * DesktopUsageAnalyzer.maxWeeklyEvents)).flatMap { week in
            let base = utc("2020-01-05T10:52:00Z").addingTimeInterval(Double(week) * 7 * 24 * 3600)
            return [
                DesktopUsageSample(time: base, org: "org-a", fiveHour: nil, weekly: 90, extra: nil),
                DesktopUsageSample(time: base.addingTimeInterval(15 * minute), org: "org-a", fiveHour: nil, weekly: 3, extra: nil),
            ]
        }
        let recent = (0..<DesktopUsageAnalyzer.maxWeeklyEvents).flatMap { week in
            let base = utc("2026-01-06T14:40:00Z").addingTimeInterval(Double(week) * 7 * 24 * 3600)
            return [
                DesktopUsageSample(time: base, org: "org-a", fiveHour: nil, weekly: 90, extra: nil),
                DesktopUsageSample(time: base.addingTimeInterval(15 * minute), org: "org-a", fiveHour: nil, weekly: 3, extra: nil),
            ]
        }
        // The recent schedule is Tuesdays 14:55; the old one Sundays 11:00.
        #expect(infer(old + recent, now: "2027-06-01T00:00:00Z") == utc("2027-06-01T14:55:00Z"))
    }

    @Test func unsortedInputIsSortedFirst() {
        let samples = [sample("2026-09-20T11:07:00Z", sd: 3), sample("2026-09-20T10:52:00Z", sd: 90)]
        #expect(infer(samples, now: "2026-09-20T11:10:00Z") == utc("2026-09-27T11:00:00Z"))
    }
}
