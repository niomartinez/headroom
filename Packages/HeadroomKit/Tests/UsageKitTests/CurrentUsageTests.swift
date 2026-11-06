import Foundation
import HeadroomModel
import Testing
@testable import UsageKit

@Suite struct CurrentUsageTests {
    @Test func zeroSamplesGiveNil() {
        #expect(DesktopUsageAnalyzer.currentUsage(samples: [], now: utc("2026-09-24T12:00:00Z")) == nil)
    }

    @Test func valuesComeFromNewestSampleOfNewestOrg() throws {
        let samples = [
            sample("2026-09-24T09:00:00Z", org: "org-a", fh: 50, sd: 60, xu: 3),
            sample("2026-09-24T10:00:00Z", org: "org-b", fh: 70, sd: 80, xu: 9),
            sample("2026-09-24T11:00:00Z", org: "org-a", fh: 55, sd: 61, xu: 4),
        ]
        let usage = try #require(DesktopUsageAnalyzer.currentUsage(samples: samples, now: utc("2026-09-24T11:05:00Z")))

        let fiveHour = try #require(usage.fiveHour)
        #expect(fiveHour.kind == .fiveHour)
        #expect(fiveHour.usedPercent == 55)
        #expect(fiveHour.source == .desktopApp)
        #expect(fiveHour.observedAt == utc("2026-09-24T11:00:00Z"))
        #expect(fiveHour.resetIsEstimated)

        let weekly = try #require(usage.weekly)
        #expect(weekly.kind == .weekly)
        #expect(weekly.usedPercent == 61)
        #expect(weekly.source == .desktopApp)
        #expect(weekly.observedAt == utc("2026-09-24T11:00:00Z"))
        #expect(weekly.resetIsEstimated)

        #expect(usage.extraUsagePercent == 4)
    }

    @Test func otherOrgsSamplesAreIgnoredForInference() throws {
        // org-b's big weekly drop must not become org-a's reset event.
        let samples = [
            sample("2026-09-20T10:52:00Z", org: "org-b", fh: 1, sd: 90),
            sample("2026-09-20T11:07:00Z", org: "org-b", fh: 1, sd: 3),
            sample("2026-09-24T11:00:00Z", org: "org-a", fh: 5, sd: 20),
        ]
        let usage = try #require(DesktopUsageAnalyzer.currentUsage(samples: samples, now: utc("2026-09-24T11:05:00Z")))
        #expect(usage.weekly?.usedPercent == 20)
        #expect(usage.weekly?.resetsAt == nil)
    }

    /// The account the desktop readings come from (spec §2.1), in any sample order.
    @Test func newestOrgIsTheNewestSamplesOrg() {
        #expect(DesktopUsageAnalyzer.newestOrg(of: []) == nil)
        #expect(DesktopUsageAnalyzer.newestOrg(of: [
            sample("2026-09-24T11:00:00Z", org: "org-a"),
            sample("2026-09-24T12:00:00Z", org: "org-b"),
            sample("2026-09-24T09:00:00Z", org: "org-c"),
        ]) == "org-b")
    }

    /// Samples with the same time keep their file order, so the later one in the file is the newest, for the
    /// org as for the readings.
    @Test func newestOrgBreaksTiesByFileOrder() throws {
        let samples = [
            sample("2026-09-24T10:00:00Z", org: "org-a", sd: 20),
            sample("2026-09-24T10:00:00Z", org: "org-b", sd: 70),
            sample("2026-09-24T09:00:00Z", org: "org-a", sd: 10),
        ]
        #expect(DesktopUsageAnalyzer.newestOrg(of: samples) == "org-b")
        let usage = try #require(DesktopUsageAnalyzer.currentUsage(samples: samples, now: utc("2026-09-24T10:05:00Z")))
        #expect(usage.weekly?.usedPercent == 70)
        #expect(DesktopUsageAnalyzer.newestOrg(of: Array(samples.reversed())) == "org-a")
    }

    @Test func unsortedInputIsHandled() throws {
        let samples = [
            sample("2026-09-24T11:00:00Z", org: "org-a", fh: 55, sd: 61),
            sample("2026-09-24T09:00:00Z", org: "org-b", fh: 50, sd: 60),
        ]
        let usage = try #require(DesktopUsageAnalyzer.currentUsage(samples: samples, now: utc("2026-09-24T11:05:00Z")))
        #expect(usage.weekly?.usedPercent == 61)
    }

    @Test func nullValuesGiveNoReadingForThatLimit() throws {
        let samples = [sample("2026-09-24T11:00:00Z", fh: nil, sd: 42, xu: nil)]
        let usage = try #require(DesktopUsageAnalyzer.currentUsage(samples: samples, now: utc("2026-09-24T11:05:00Z")))
        #expect(usage.fiveHour == nil)
        #expect(usage.weekly?.usedPercent == 42)
        #expect(usage.extraUsagePercent == nil)
    }

    @Test func newestSampleWithoutValuesGivesNil() {
        let samples = [sample("2026-09-24T10:00:00Z", fh: 5, sd: 5), sample("2026-09-24T11:00:00Z")]
        #expect(DesktopUsageAnalyzer.currentUsage(samples: samples, now: utc("2026-09-24T11:05:00Z")) == nil)
    }

    @Test func fiveHourZeroMeansNotStarted() throws {
        let samples = [sample("2026-09-24T10:45:00Z", fh: 30, sd: 50), sample("2026-09-24T11:00:00Z", fh: 0, sd: 50)]
        let usage = try #require(DesktopUsageAnalyzer.currentUsage(samples: samples, now: utc("2026-09-24T11:05:00Z")))
        #expect(usage.fiveHour?.usedPercent == 0)
        #expect(usage.fiveHour?.resetsAt == nil)
    }

    @Test func resetsAreInferred() throws {
        let samples = [
            sample("2026-09-20T10:52:00Z", fh: 0, sd: 90),
            sample("2026-09-20T11:07:00Z", fh: 0, sd: 3),
            sample("2026-09-24T09:45:00Z", fh: 0, sd: 30),
            sample("2026-09-24T10:00:00Z", fh: 4, sd: 31),
            sample("2026-09-24T10:15:00Z", fh: 9, sd: 32),
        ]
        let usage = try #require(DesktopUsageAnalyzer.currentUsage(samples: samples, now: utc("2026-09-24T10:20:00Z")))
        #expect(usage.weekly?.resetsAt == utc("2026-09-27T11:00:00Z"))
        #expect(usage.fiveHour?.resetsAt == utc("2026-09-24T14:52:30Z"))
    }

    @Test func resetThatPassedSinceTheNewestSampleStaysVisible() throws {
        // Inference runs as of the newest sample, so the resolver can roll the reading over (§3.1)
        // instead of showing pre-reset usage with next week's reset time.
        let samples = [
            sample("2026-09-13T10:52:00Z", fh: 0, sd: 90),
            sample("2026-09-13T11:07:00Z", fh: 0, sd: 3),
            sample("2026-09-20T09:00:00Z", fh: 40, sd: 88),
        ]
        let usage = try #require(DesktopUsageAnalyzer.currentUsage(samples: samples, now: utc("2026-09-21T09:00:00Z")))
        #expect(usage.weekly?.resetsAt == utc("2026-09-20T11:00:00Z"))
        #expect(usage.fiveHour?.resetsAt == utc("2026-09-20T13:52:30Z"))
    }
}
