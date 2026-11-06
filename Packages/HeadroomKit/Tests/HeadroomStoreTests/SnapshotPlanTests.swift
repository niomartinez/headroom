import Foundation
import HeadroomModel
import Testing
@testable import HeadroomStore

/// Plan limits from the desktop history and the terminal status line (spec §2.1, §2.4, §3.1).
@Suite struct SnapshotPlanTests {
    @Test func desktopOnly() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeDesktopHistory([
            HistorySample(time: testNow - 40 * minute, fiveHour: 10, weekly: 88),
            HistorySample(time: testNow - 25 * minute, fiveHour: 12, weekly: 88),
            HistorySample(time: testNow - 10 * minute, fiveHour: 14, weekly: 89, extra: 12),
        ])

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe()).build(access: .full, now: testNow)

        let fiveHour = try #require(snapshot.plan.fiveHour)
        let weekly = try #require(snapshot.plan.weekly)
        #expect(fiveHour.usedPercent == 14)
        #expect(fiveHour.source == .desktopApp)
        #expect(fiveHour.observedAt == testNow - 10 * minute)
        #expect(fiveHour.resetIsEstimated)
        #expect(fiveHour.resetsAt != nil)
        #expect(weekly.usedPercent == 89)
        #expect(weekly.source == .desktopApp)
        #expect(snapshot.plan.extraUsagePercent == 12)
        #expect(snapshot.issues.isEmpty)
        #expect(snapshot.generatedAt == testNow)
    }

    @Test func terminalOnly() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        let fiveHourReset = testNow + 2 * hour
        let weeklyReset = testNow + 72 * hour
        try tree.writeStatusLineLatest(
            fiveHour: (20, fiveHourReset), weekly: (90, weeklyReset), modified: testNow - minute)

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe()).build(access: .full, now: testNow)

        let fiveHour = try #require(snapshot.plan.fiveHour)
        let weekly = try #require(snapshot.plan.weekly)
        #expect(fiveHour.usedPercent == 20)
        #expect(fiveHour.source == .terminal)
        #expect(fiveHour.resetsAt == fiveHourReset)
        #expect(!fiveHour.resetIsEstimated)
        #expect(fiveHour.observedAt == testNow - minute)
        #expect(weekly.usedPercent == 90)
        #expect(weekly.resetsAt == weeklyReset)
        #expect(snapshot.plan.extraUsagePercent == nil)
        // No desktop history file is not a problem (terminal-only users).
        #expect(snapshot.issues.isEmpty)
    }

    @Test func mixedNewestReadingWins() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeDesktopHistory([
            HistorySample(time: testNow - 25 * minute, fiveHour: 28, weekly: 50),
            HistorySample(time: testNow - 10 * minute, fiveHour: 30, weekly: 50, extra: 3),
        ])
        try tree.writeStatusLineLatest(
            fiveHour: (32, testNow + hour), weekly: (51, testNow + 48 * hour), modified: testNow - 2 * minute)

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe()).build(access: .full, now: testNow)

        #expect(snapshot.plan.fiveHour?.usedPercent == 32)
        #expect(snapshot.plan.fiveHour?.source == .terminal)
        #expect(snapshot.plan.weekly?.usedPercent == 51)
        #expect(snapshot.plan.weekly?.source == .terminal)
        // Extra usage only ever comes from the desktop.
        #expect(snapshot.plan.extraUsagePercent == 3)
    }

    @Test func mixedNewerDesktopReadingBorrowsTheExactReset() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        let exactWeeklyReset = testNow + 48 * hour
        try tree.writeStatusLineLatest(
            fiveHour: (30, testNow + hour), weekly: (50, exactWeeklyReset), modified: testNow - 30 * minute)
        try tree.writeDesktopHistory([
            HistorySample(time: testNow - 40 * minute, fiveHour: 29, weekly: 50),
            HistorySample(time: testNow - 5 * minute, fiveHour: 34, weekly: 52),
        ])

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe()).build(access: .full, now: testNow)

        let weekly = try #require(snapshot.plan.weekly)
        #expect(weekly.usedPercent == 52)
        #expect(weekly.source == .desktopApp)
        #expect(weekly.resetsAt == exactWeeklyReset)
        #expect(!weekly.resetIsEstimated)
    }

    @Test func noSourcesGiveAnEmptyPlan() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe()).build(access: .full, now: testNow)

        #expect(snapshot.plan == .empty)
        #expect(snapshot.sessions.isEmpty)
        #expect(!snapshot.terminalBridgeConnected)
        #expect(snapshot.issues.isEmpty)
        #expect(snapshot.generatedAt == testNow)
    }
}

/// Spec §2.1: an unrecognized history file may be caught mid-write; the last good samples are kept for 5 min.
@Suite struct UnrecognizedDesktopUsageTests {
    private func writeGood(_ tree: FixtureTree, modified: Date) throws {
        try tree.writeDesktopHistory([
            HistorySample(time: testNow - 20 * minute, fiveHour: 40, weekly: 70),
            HistorySample(time: testNow - 5 * minute, fiveHour: 41, weekly: 71),
        ], modified: modified)
    }

    private func writeCorrupt(_ tree: FixtureTree, modified: Date) throws {
        try tree.write(#"{"version":2,"samples":[{"t":17"#, to: tree.paths.planUsageHistoryFile, modified: modified)
    }

    @Test func keepsTheLastGoodSamplesForFiveMinutesThenReportsTheIssue() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try writeGood(tree, modified: testNow - 5 * minute)
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe())
        #expect(builder.build(access: .full, now: testNow).plan.weekly?.usedPercent == 71)

        try writeCorrupt(tree, modified: testNow + 2 * second)
        let failedAt = testNow + 2 * second
        let during = builder.build(access: .full, now: failedAt)
        #expect(during.plan.weekly?.usedPercent == 71)
        #expect(!during.issues.contains(.desktopUsageUnrecognized))

        let stillDuring = builder.build(access: .full, now: failedAt + 5 * minute - second)
        #expect(stillDuring.plan.weekly?.usedPercent == 71)
        #expect(!stillDuring.issues.contains(.desktopUsageUnrecognized))

        let after = builder.build(access: .full, now: failedAt + 5 * minute)
        #expect(after.plan.weekly == nil)
        #expect(after.plan.fiveHour == nil)
        #expect(after.issues.contains(.desktopUsageUnrecognized))

        // The samples were dropped, not just hidden: they don't come back while the file stays unrecognized.
        let later = builder.build(access: .full, now: failedAt + 10 * minute)
        #expect(later.plan.weekly == nil)
        #expect(later.issues.contains(.desktopUsageUnrecognized))
    }

    @Test func aFileRewrittenCorrectlyWithinTheGraceClearsIt() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try writeGood(tree, modified: testNow - 5 * minute)
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe())
        _ = builder.build(access: .full, now: testNow)

        try writeCorrupt(tree, modified: testNow + 2 * second)
        _ = builder.build(access: .full, now: testNow + 2 * second)
        try tree.writeDesktopHistory([
            HistorySample(time: testNow - 20 * minute, fiveHour: 40, weekly: 70),
            HistorySample(time: testNow + 3 * second, fiveHour: 42, weekly: 72),
        ], modified: testNow + 4 * second)

        let recovered = builder.build(access: .full, now: testNow + 4 * second)
        #expect(recovered.plan.weekly?.usedPercent == 72)
        // A later failure starts a fresh grace period.
        try writeCorrupt(tree, modified: testNow + 10 * minute)
        let again = builder.build(access: .full, now: testNow + 10 * minute)
        #expect(again.plan.weekly?.usedPercent == 72)
        #expect(!again.issues.contains(.desktopUsageUnrecognized))
    }

    @Test func unknownVersionWithoutEarlierSamplesIsReportedAtOnce() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeDesktopHistory([HistorySample(time: testNow - 5 * minute, fiveHour: 41, weekly: 71)], version: "3")

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe()).build(access: .full, now: testNow)

        #expect(snapshot.plan == .empty)
        #expect(snapshot.issues == [.desktopUsageUnrecognized])
    }

    @Test func aMissingFileIsNotAnIssueAndDropsTheSamples() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try writeGood(tree, modified: testNow - 5 * minute)
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe())
        _ = builder.build(access: .full, now: testNow)

        try FileManager.default.removeItem(at: tree.paths.planUsageHistoryFile)
        let snapshot = builder.build(access: .full, now: testNow + 2 * second)

        #expect(snapshot.plan == .empty)
        #expect(snapshot.issues.isEmpty)
    }
}
