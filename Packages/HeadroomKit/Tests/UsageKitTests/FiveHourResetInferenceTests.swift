import Foundation
import Testing
@testable import UsageKit

@Suite struct FiveHourResetInferenceTests {
    private func infer(_ samples: [DesktopUsageSample], now: String) -> Date? {
        DesktopUsageAnalyzer.inferFiveHourReset(samples: samples, now: utc(now))
    }

    @Test func newestZeroMeansNoActiveWindow() {
        let samples = [sample("2026-09-24T10:00:00Z", fh: 40), sample("2026-09-24T10:15:00Z", fh: 0)]
        #expect(infer(samples, now: "2026-09-24T10:20:00Z") == nil)
        #expect(infer([], now: "2026-09-24T10:20:00Z") == nil)
    }

    @Test func runStartsHalfAGapBeforeItsFirstSample() {
        let samples = [
            sample("2026-09-24T09:45:00Z", fh: 0),
            sample("2026-09-24T10:00:00Z", fh: 4),
            sample("2026-09-24T10:15:00Z", fh: 9),
            sample("2026-09-24T10:30:00Z", fh: 15),
        ]
        #expect(infer(samples, now: "2026-09-24T10:35:00Z") == utc("2026-09-24T14:52:30Z"))
    }

    @Test func halfGapIsCappedAtSevenAndAHalfMinutes() {
        let long = [sample("2026-09-24T08:00:00Z", fh: 0), sample("2026-09-24T10:00:00Z", fh: 4)]
        #expect(infer(long, now: "2026-09-24T10:05:00Z") == utc("2026-09-24T14:52:30Z"))

        let short = [sample("2026-09-24T09:54:00Z", fh: 0), sample("2026-09-24T10:00:00Z", fh: 4)]
        #expect(infer(short, now: "2026-09-24T10:05:00Z") == utc("2026-09-24T14:57:00Z"))
    }

    @Test func dropOfTenOrMorePointsStartsANewRun() {
        let samples = [
            sample("2026-09-24T10:00:00Z", fh: 40),
            sample("2026-09-24T10:15:00Z", fh: 45),
            sample("2026-09-24T10:30:00Z", fh: 5),
            sample("2026-09-24T10:45:00Z", fh: 8),
        ]
        #expect(infer(samples, now: "2026-09-24T10:50:00Z") == utc("2026-09-24T15:22:30Z"))
    }

    @Test func anySmallerDropAlsoStartsANewRun() {
        // Usage inside one window never goes down; the real history has resets that dropped only 3–5 points.
        let samples = [
            sample("2026-09-24T01:30:00Z", fh: 0),
            sample("2026-09-24T01:45:00Z", fh: 10),
            sample("2026-09-24T06:15:00Z", fh: 7),
            sample("2026-09-24T06:30:00Z", fh: 9),
        ]
        #expect(infer(samples, now: "2026-09-24T06:35:00Z") == utc("2026-09-24T11:07:30Z"))
    }

    @Test func gapOfFiveHoursOrMoreBreaksTheRun() {
        let fiveHours = [
            sample("2026-09-24T03:45:00Z", fh: 0),
            sample("2026-09-24T04:00:00Z", fh: 10),
            sample("2026-09-24T09:00:00Z", fh: 12),
        ]
        #expect(infer(fiveHours, now: "2026-09-24T09:05:00Z") == utc("2026-09-24T13:52:30Z"))

        let justUnder = [
            sample("2026-09-24T03:45:00Z", fh: 0),
            sample("2026-09-24T04:00:00Z", fh: 10),
            sample("2026-09-24T08:59:59Z", fh: 12),
        ]
        #expect(infer(justUnder, now: "2026-09-24T08:50:00Z") == utc("2026-09-24T08:52:30Z"))
    }

    @Test func resetAlreadyPastGivesNil() {
        let samples = [sample("2026-09-24T09:45:00Z", fh: 0), sample("2026-09-24T10:00:00Z", fh: 4)]
        #expect(infer(samples, now: "2026-09-24T14:52:29Z") == utc("2026-09-24T14:52:30Z"))
        #expect(infer(samples, now: "2026-09-24T14:52:30Z") == nil)
        #expect(infer(samples, now: "2026-09-24T16:00:00Z") == nil)
    }

    @Test func runReachingTheFirstSampleStartsAtThatSample() {
        let samples = [sample("2026-09-24T10:00:00Z", fh: 4), sample("2026-09-24T10:15:00Z", fh: 9)]
        #expect(infer(samples, now: "2026-09-24T10:20:00Z") == utc("2026-09-24T15:00:00Z"))
    }

    @Test func onlyTheNewestOrgCounts() {
        let samples = [
            sample("2026-09-24T09:45:00Z", org: "org-a", fh: 0),
            sample("2026-09-24T10:00:00Z", org: "org-b", fh: 30),
            sample("2026-09-24T10:15:00Z", org: "org-a", fh: 4),
        ]
        #expect(infer(samples, now: "2026-09-24T10:20:00Z") == utc("2026-09-24T15:07:30Z"))
    }

    @Test func samplesWithoutFiveHourValueAreSkipped() {
        let samples = [
            sample("2026-09-24T09:45:00Z", fh: 0, sd: 1),
            sample("2026-09-24T09:50:00Z", fh: nil, sd: 1),
            sample("2026-09-24T10:00:00Z", fh: 4, sd: 1),
        ]
        #expect(infer(samples, now: "2026-09-24T10:05:00Z") == utc("2026-09-24T14:52:30Z"))
    }
}
