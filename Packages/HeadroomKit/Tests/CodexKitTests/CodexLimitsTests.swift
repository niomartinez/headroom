import Foundation
import HeadroomModel
import Testing
@testable import CodexKit

/// Plan limits from the rollouts (1.1 §3.4), through `CodexReader`.
@Suite struct CodexLimitsTests {
    private func usage(_ fixtures: [String], now: Date = testNow) throws -> CodexReading {
        let home = try CodexHome()
        for fixture in fixtures { try home.install(fixture) }
        return home.reader(running: false).read(now: now)
    }

    @Test func plusHasFiveHourAndWeekly() throws {
        let reading = try usage(["plus_5h_weekly"])
        let usage = reading.usage
        #expect(usage.tool == .codex)
        #expect(usage.status == .ok)
        #expect(usage.planName == "Plus")
        #expect(usage.hasFiveHourWindow)
        #expect(usage.limits == [
            ToolLimit(window: .weekly, usedPercent: 55, resetsAt: date("2026-09-27T09:00:00Z"), observedAt: date("2026-09-23T10:02:00Z")),
            ToolLimit(window: .fiveHour, usedPercent: 17, resetsAt: date("2026-09-23T14:00:00Z"), observedAt: date("2026-09-23T10:02:00Z")),
        ])
        #expect(usage.staleAfter == 30 * 60)
        #expect(reading.issues.isEmpty)
    }

    @Test func proHasWeeklyInPrimaryOnly() throws {
        let usage = try usage(["pro_weekly_primary"]).usage
        #expect(usage.planName == "Pro")
        #expect(!usage.hasFiveHourWindow)
        #expect(usage.limits.map(\.window) == [.weekly])
        #expect(usage.limits.first?.usedPercent == 42)
    }

    @Test func otherBucketsSitBesideTheRings() throws {
        let usage = try usage(["mixed_codex_spark"]).usage
        #expect(usage.limits.map(\.usedPercent) == [94, 20])
        #expect(usage.otherBuckets.count == 1)
        #expect(usage.otherBuckets.first?.id == "codex_bengalfox")
        #expect(usage.otherBuckets.first?.name == "GPT-5.3-Codex-Spark")
        #expect(usage.otherBuckets.first?.limits.map(\.usedPercent) == [80, 10])
    }

    @Test func premiumWithoutWindowsIsIgnored() throws {
        let reading = try usage(["premium_null"])
        #expect(reading.usage.status == .ok)
        #expect(reading.usage.limits.map(\.usedPercent) == [33])
        #expect(reading.usage.otherBuckets.isEmpty)
        #expect(reading.issues.isEmpty)
    }

    /// A `codex` object whose windows are all null (or one with only credits and plan, whose `limit_id` defaults to
    /// `codex`) has no numbers: like `premium`, it is ignored, so an older reading with windows still shows, in the
    /// same file or an older one (1.1 §3.4). It doesn't stop the search either.
    @Test func aNewerCodexReadingWithoutWindowsDoesNotHideAnOlderOne() throws {
        let emptyCodex = #"{"limit_id":"codex","limit_name":null,"primary":null,"secondary":null,"credits":{"has_credits":false,"unlimited":false,"balance":"0"},"plan_type":"pro"}"#
        let creditsOnly = #"{"credits":{"has_credits":true,"unlimited":false,"balance":"5"},"plan_type":"pro"}"#

        // In the same file.
        let home = try CodexHome()
        let id = RolloutText.threadID(created: date("2026-09-23T12:00:00Z"), salt: 11)
        try home.installText(
            RolloutText.meta(id, at: "2026-09-23T12:00:00.000Z")
                + RolloutText.tokenCount(at: "2026-09-23T12:10:00.000Z", rateLimits: RolloutText.weekly(61))
                + RolloutText.tokenCount(at: "2026-09-23T12:20:00.000Z", rateLimits: emptyCodex)
                + RolloutText.tokenCount(at: "2026-09-23T12:30:00.000Z", rateLimits: creditsOnly),
            threadID: id
        )
        let reading = home.reader(running: false).read(now: testNow)
        #expect(reading.usage.status == .ok)
        #expect(reading.usage.limits.map(\.usedPercent) == [61])
        #expect(reading.usage.limits.first?.observedAt == date("2026-09-23T12:10:00Z"))
        #expect(reading.issues.isEmpty)

        // In a newer file: the older file is still searched.
        let other = try CodexHome()
        try other.install("pro_weekly_primary")  // 42% at 11:05
        let newer = RolloutText.threadID(created: date("2026-09-23T13:00:00Z"), salt: 12)
        try other.installText(
            RolloutText.meta(newer, at: "2026-09-23T13:00:00.000Z")
                + RolloutText.tokenCount(at: "2026-09-23T13:10:00.000Z", rateLimits: emptyCodex),
            threadID: newer
        )
        let usage = other.reader(running: false).read(now: testNow).usage
        #expect(usage.status == .ok)
        #expect(usage.limits.map(\.usedPercent) == [42])
    }

    /// Only readings without windows: no limits found, as with none at all.
    @Test func onlyReadingsWithoutWindowsIsNoActivity() throws {
        let home = try CodexHome()
        let id = RolloutText.threadID(created: date("2026-09-23T12:00:00Z"), salt: 13)
        try home.installText(
            RolloutText.meta(id, at: "2026-09-23T12:00:00.000Z")
                + RolloutText.tokenCount(at: "2026-09-23T12:10:00.000Z", rateLimits: #"{"limit_id":"codex","primary":null,"secondary":null}"#),
            threadID: id
        )
        let reading = home.reader(running: false).read(now: testNow)
        #expect(reading.usage.status == .noActivity)
        #expect(reading.issues.isEmpty)
    }

    @Test func noReadingsIsNoActivity() throws {
        let reading = try usage(["rate_limits_null", "cli_source", "imported_claude"])
        #expect(reading.usage.status == .noActivity)
        #expect(reading.usage.limits.isEmpty)
        #expect(reading.issues.isEmpty)
        #expect(try usage([]).usage.status == .noActivity)
    }

    @Test func legacyFormats() throws {
        let inSeconds = try usage(["legacy_resets_in_seconds"], now: date("2026-09-23T09:30:00Z")).usage
        #expect(inSeconds.limits == [
            ToolLimit(window: .weekly, usedPercent: 40, resetsAt: date("2026-09-24T09:01:00Z"), observedAt: date("2026-09-23T09:01:00Z")),
            ToolLimit(window: .fiveHour, usedPercent: 12.5, resetsAt: date("2026-09-23T11:01:00Z"), observedAt: date("2026-09-23T09:01:00Z")),
        ])
        #expect(inSeconds.planName == nil)

        let flat = try usage(["legacy_flat"], now: date("2026-09-23T09:30:00Z")).usage
        #expect(flat.limits.map(\.window) == [.weekly, .fiveHour])
        #expect(flat.limits.map(\.usedPercent) == [40, 12.5])
        #expect(flat.limits.allSatisfy { $0.resetsAt == nil && !$0.resetSinceReading })

        let noMinutes = try usage(["missing_window_minutes"], now: date("2026-09-23T09:00:00Z")).usage
        #expect(noMinutes.limits.map(\.window) == [.weekly, .fiveHour])
        #expect(noMinutes.limits.map(\.usedPercent) == [60, 30])

        let noID = try usage(["missing_limit_id"]).usage
        #expect(noID.status == .ok)
        #expect(noID.limits.map(\.usedPercent) == [42])
        #expect(noID.planName == "Pro Lite")
    }

    @Test func subagentReadingsCount() throws {
        // The subagent's 12:45 reading is newer than the root thread's 12:01 one.
        let usage = try usage(["mixed_codex_spark", "subagent"]).usage
        #expect(usage.limits.map(\.usedPercent) == [95, 25])
    }

    @Test func importedThreadsDontCount() throws {
        let home = try CodexHome()
        try home.install("mixed_codex_spark")
        try home.install("subagent")
        try home.installImports(#"{"records":[{"imported_thread_id":"\#(CodexFixtures.threadID("subagent"))","imported_at":1790000000}]}"#)
        let usage = home.reader(running: false).read(now: testNow).usage
        #expect(usage.limits.map(\.usedPercent) == [94, 20])
    }

    @Test func errorLinesDontChangeTheNumbers() throws {
        // `usage_limit_exceeded` and `rate_limit_reached_type` are ignored: Codex's numbers as they are.
        let usage = try usage(["error_usage_limit"]).usage
        #expect(usage.limits.map(\.usedPercent) == [100])
    }

    // MARK: - Newest reading by event time (§3.4)

    @Test func newestReadingIsByTimestampNotModificationTime() throws {
        let home = try CodexHome()
        try home.install("pro_weekly_primary")  // reading at 11:05
        // Rewritten later: newest modification time, older events (reading at 10:02).
        try home.install("plus_5h_weekly", modified: date("2026-09-23T13:00:00Z"))
        let usage = home.reader(running: false).read(now: testNow).usage
        #expect(usage.planName == "Pro")
        #expect(usage.limits.first?.observedAt == date("2026-09-23T11:05:00Z"))
    }

    @Test func olderFilesAreNotReadOnceTheBestReadingIsNewer() throws {
        let home = try CodexHome()
        try home.install("pro_weekly_primary")  // reading 11:05, modified 11:05:02
        try home.install("plus_5h_weekly")  // modified 10:02:02
        try home.install("legacy_flat")  // modified 08:01:02
        let reader = home.reader(running: false)
        let usage = reader.read(now: testNow).usage
        #expect(usage.planName == "Pro")
        #expect(reader.files.opens == 1)
    }

    @Test func aFileModifiedWithinASecondOfTheBestReadingIsStillRead() throws {
        let home = try CodexHome()
        try home.install("pro_weekly_primary")  // reading 11:05:00
        try home.install("plus_5h_weekly", modified: date("2026-09-23T11:04:59.500Z"))
        try home.install("legacy_flat", modified: date("2026-09-23T11:04:58.500Z"))
        let reader = home.reader(running: false)
        _ = reader.read(now: testNow)
        #expect(reader.files.opens == 2)
    }

    @Test func unchangedFilesAreNotReadAgain() throws {
        let home = try CodexHome()
        try home.install("pro_weekly_primary")
        try home.install("plus_5h_weekly")
        let reader = home.reader(running: false)
        _ = reader.read(now: testNow)
        reader.files.resetCounters()
        // A later walk finds the same files.
        let usage = reader.read(now: testNow.addingTimeInterval(60)).usage
        #expect(usage.planName == "Pro")
        #expect(reader.files.opens == 0)
    }

    @Test func aNewerReadingInAGrowingFileIsPickedUp() throws {
        let home = try CodexHome()
        let url = try home.install("pro_weekly_primary")
        let reader = home.reader(running: false)
        #expect(reader.read(now: testNow).usage.limits.first?.usedPercent == 42)
        try home.append(RolloutText.tokenCount(at: "2026-09-23T13:41:00.000Z", rateLimits: RolloutText.weekly(47)), to: url,
                        modified: date("2026-09-23T13:41:01Z"))
        let before = reader.tailBytesRead
        let usage = reader.read(now: testNow.addingTimeInterval(120)).usage
        #expect(usage.limits.first?.usedPercent == 47)
        #expect(usage.limits.first?.observedAt == date("2026-09-23T13:41:00Z"))
        // Only the appended line was read.
        #expect(reader.tailBytesRead - before < 1_000)
    }

    // MARK: - Rollover and staleness

    @Test func windowsRollOverPastTheirReset() throws {
        let afterFiveHour = try usage(["plus_5h_weekly"], now: date("2026-09-23T14:30:00Z")).usage
        let fiveHour = afterFiveHour.limit(.fiveHour)
        #expect(fiveHour?.usedPercent == 0)
        #expect(fiveHour?.resetsAt == nil)
        #expect(afterFiveHour.limit(.weekly)?.usedPercent == 55)

        let afterWeekly = try usage(["plus_5h_weekly"], now: date("2026-09-27T10:00:00Z")).usage
        let weekly = afterWeekly.limit(.weekly)
        #expect(weekly?.usedPercent == 0)
        #expect(weekly?.resetsAt == nil)
        #expect(weekly?.resetSinceReading == true)
    }

    @Test func readingsGoStaleAfterThirtyMinutes() throws {
        let usage = try usage(["plus_5h_weekly"]).usage
        #expect(!usage.isStale(now: date("2026-09-23T10:31:00Z")))
        #expect(usage.isStale(now: date("2026-09-23T10:33:00Z")))
    }

    // MARK: - Unrecognized (§3.4)

    private let unknownShape = #"{"limit_id":"codex","primary":{"weird":1}}"#

    @Test func anUnknownNewestReadingIsUnrecognized() throws {
        let home = try CodexHome()
        let id = RolloutText.threadID(created: date("2026-09-23T13:00:00Z"), salt: 1)
        try home.installText(
            RolloutText.meta(id, at: "2026-09-23T13:00:00.000Z")
                + RolloutText.tokenCount(at: "2026-09-23T13:10:00.000Z", rateLimits: unknownShape),
            threadID: id
        )
        let reading = home.reader(running: false).read(now: testNow)
        #expect(reading.usage.status == .unrecognized)
        #expect(reading.usage.limits.isEmpty)
        #expect(reading.issues == [.codexUsageUnrecognized])
    }

    @Test func anOlderUnknownReadingDoesNotMatter() throws {
        let home = try CodexHome()
        try home.install("pro_weekly_primary")  // 11:05
        let id = RolloutText.threadID(created: date("2026-09-23T10:00:00Z"), salt: 2)
        try home.installText(
            RolloutText.meta(id, at: "2026-09-23T10:00:00.000Z")
                + RolloutText.tokenCount(at: "2026-09-23T11:04:00.000Z", rateLimits: unknownShape),
            threadID: id, modified: date("2026-09-23T11:06:00Z")
        )
        let reading = home.reader(running: false).read(now: testNow)
        #expect(reading.usage.status == .ok)
        #expect(reading.issues.isEmpty)
    }

    /// A known empty reading (all windows null) newer than an unknown one: the newest `rate_limits` is a known shape.
    @Test func anUnknownReadingBeforeAnEmptyOneDoesNotMatter() throws {
        let home = try CodexHome()
        try home.install("pro_weekly_primary")  // 11:05
        let id = RolloutText.threadID(created: date("2026-09-23T13:00:00Z"), salt: 14)
        try home.installText(
            RolloutText.meta(id, at: "2026-09-23T13:00:00.000Z")
                + RolloutText.tokenCount(at: "2026-09-23T13:10:00.000Z", rateLimits: unknownShape)
                + RolloutText.tokenCount(at: "2026-09-23T13:20:00.000Z", rateLimits: #"{"limit_id":"premium","primary":null,"secondary":null}"#),
            threadID: id
        )
        let reading = home.reader(running: false).read(now: testNow)
        #expect(reading.usage.status == .ok)
        #expect(reading.usage.limits.map(\.usedPercent) == [42])
        #expect(reading.issues.isEmpty)
    }

    @Test func theLastGoodReadingIsKeptForFiveMinutes() throws {
        let home = try CodexHome()
        try home.install("pro_weekly_primary")
        let reader = home.reader(running: false)
        #expect(reader.read(now: testNow).usage.status == .ok)

        let id = RolloutText.threadID(created: date("2026-09-23T13:40:00Z"), salt: 3)
        try home.installText(
            RolloutText.meta(id, at: "2026-09-23T13:40:00.000Z")
                + RolloutText.tokenCount(at: "2026-09-23T13:40:10.000Z", rateLimits: unknownShape),
            threadID: id
        )
        let held = reader.read(now: testNow.addingTimeInterval(60))
        #expect(held.usage.status == .ok)
        #expect(held.usage.limits.first?.usedPercent == 42)
        #expect(held.issues.isEmpty)

        let expired = reader.read(now: testNow.addingTimeInterval(60 + 5 * 60))
        #expect(expired.usage.status == .unrecognized)
        #expect(expired.issues == [.codexUsageUnrecognized])

        // A recognized reading again clears it.
        try home.append(RolloutText.tokenCount(at: "2026-09-23T13:47:00.000Z", rateLimits: RolloutText.weekly(50)),
                        to: home.install("pro_weekly_primary"), modified: date("2026-09-23T13:47:01Z"))
        let recovered = reader.read(now: testNow.addingTimeInterval(8 * 60))
        #expect(recovered.usage.status == .ok)
        #expect(recovered.usage.limits.first?.usedPercent == 50)
        #expect(recovered.issues.isEmpty)
    }

    // MARK: - Folder problems (§3.6)

    @Test func aMissingSessionsFolderIsJustEmpty() throws {
        let home = try CodexHome()
        try FileManager.default.removeItem(at: home.paths.sessionsDirectory)
        let reading = home.reader().read(now: testNow)
        #expect(reading.usage.status == .noActivity)
        #expect(reading.sessions.isEmpty)
        #expect(reading.issues.isEmpty)
    }

    @Test func anUnreadableSessionsFolderIsAnIssue() throws {
        let home = try CodexHome()
        try FileManager.default.removeItem(at: home.paths.sessionsDirectory)
        // A file where the folder should be can't be listed.
        try home.write("", to: home.paths.sessionsDirectory)
        let reading = home.reader().read(now: testNow)
        #expect(reading.issues == [.codexSessionsUnreadable])
        #expect(reading.sessions.isEmpty)
        #expect(reading.usage.status == .noActivity)
    }
}
