import Foundation
import HeadroomModel
import Testing
@testable import HeadroomStore

/// Moments from real builds (spec §3.4): the builder's snapshots must carry what `MomentDetector` needs.
@Suite struct SnapshotMomentTests {
    /// A terminal session's bridge files are rewritten while it works (a status line refresh on every message
    /// update), so its newest write is always a second or two old. That must not hide the finish of a long run.
    @Test func aTerminalSessionThatWorkedForAMinuteFinishes() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        let start = testNow - minute
        try tree.writeBridgeHook(sessionId: "term-1", pid: 201, event: "UserPromptSubmit", at: start)
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [201]))

        // Polls every 2 s while the reply streams in: the status line was refreshed a second before each poll.
        var previous: HeadroomSnapshot?
        for poll in stride(from: start, to: testNow, by: 2 * second) {
            try tree.writeBridgeStatusLine(
                sessionId: "term-1", pid: 201, at: poll - second, model: "claude-opus-5-5", contextWindowSize: 1_000_000)
            let snapshot = builder.build(access: .full, now: poll)
            #expect(snapshot.sessions.first?.activity == .working)
            #expect(MomentDetector.moments(previous: previous, current: snapshot).isEmpty)
            previous = snapshot
        }

        try tree.writeBridgeStatusLine(
            sessionId: "term-1", pid: 201, at: testNow - second, model: "claude-opus-5-5", contextWindowSize: 1_000_000)
        try tree.writeBridgeHook(sessionId: "term-1", pid: 201, event: "Stop", at: testNow - second)
        let finished = builder.build(access: .full, now: testNow)

        #expect(finished.sessions.first?.activity == .idle)
        #expect(MomentDetector.moments(previous: previous, current: finished) == [
            .sessionFinished(sessionID: "term-1", name: "terminal-tool"),
        ])
    }

    /// The other side of the guard still holds for terminal sessions: a burst of work under 5 s is not a finish.
    @Test func aTerminalSessionsBriefBurstIsNotAFinish() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeBridgeHook(sessionId: "term-1", pid: 201, event: "Stop", at: testNow - hour)
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [201]))
        _ = builder.build(access: .full, now: testNow - 4 * second)

        try tree.writeBridgeHook(sessionId: "term-1", pid: 201, event: "UserPromptSubmit", at: testNow - 3 * second)
        let working = builder.build(access: .full, now: testNow - 2 * second)
        #expect(working.sessions.first?.activity == .working)

        try tree.writeBridgeHook(sessionId: "term-1", pid: 201, event: "Stop", at: testNow - second)
        let idle = builder.build(access: .full, now: testNow)

        #expect(idle.sessions.first?.activity == .idle)
        #expect(MomentDetector.moments(previous: working, current: idle).isEmpty)
    }

    /// A long run's start is not carried into the next one: after going idle, a brief new run is not a finish.
    @Test func aNewRunStartsAfresh() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeBridgeHook(sessionId: "term-1", pid: 201, event: "UserPromptSubmit", at: testNow - hour)
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [201]))
        _ = builder.build(access: .full, now: testNow - hour)

        try tree.writeBridgeHook(sessionId: "term-1", pid: 201, event: "Stop", at: testNow - 10 * second)
        _ = builder.build(access: .full, now: testNow - 10 * second)
        try tree.writeBridgeHook(sessionId: "term-1", pid: 201, event: "UserPromptSubmit", at: testNow - 3 * second)
        let working = builder.build(access: .full, now: testNow - 2 * second)
        #expect(working.sessions.first?.activitySince == testNow - 3 * second)

        try tree.writeBridgeHook(sessionId: "term-1", pid: 201, event: "Stop", at: testNow - second)
        let idle = builder.build(access: .full, now: testNow)

        #expect(MomentDetector.moments(previous: working, current: idle).isEmpty)
    }

    /// A desktop session's registry `statusUpdatedAt` already says when it started working: a finish after a long
    /// run is announced, one right after the status changed is not.
    @Test func desktopSessionsFinishByTheirRegistryStatusTime() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeRegistryEntry(sessionId: "desk-long", pid: 101, status: "busy", statusUpdatedAt: testNow - 10 * minute)
        try tree.writeRegistryEntry(sessionId: "desk-brief", pid: 102, status: "busy", statusUpdatedAt: testNow - 3 * second)
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101, 102]))
        let working = builder.build(access: .full, now: testNow - 2 * second)

        try tree.writeRegistryEntry(sessionId: "desk-long", pid: 101, status: "idle", statusUpdatedAt: testNow - second)
        try tree.writeRegistryEntry(sessionId: "desk-brief", pid: 102, status: "idle", statusUpdatedAt: testNow - second)
        let idle = builder.build(access: .full, now: testNow)

        #expect(MomentDetector.moments(previous: working, current: idle) == [
            .sessionFinished(sessionID: "desk-long", name: "Polish onboarding copy"),
        ])
    }

    // MARK: - Desktop account switches (spec §2.1)

    /// The shape of the real history (2026-09-22): org B at 87 % weekly, then the desktop app switched to org A,
    /// which had been at 100 % for 17 hours. The weekly reading rose 13 points across 90 and 100, but no usage
    /// crossed anything: it was another account's.
    @Test func aDesktopAccountSwitchIsNotALimitCrossing() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        let orgA = HistorySample(time: testNow - 17 * hour, org: "org-a", fiveHour: 0, weekly: 100)
        let orgB = HistorySample(time: testNow - 10 * minute, org: "org-b", fiveHour: 20, weekly: 87)
        try tree.writeDesktopHistory([orgA, orgB])
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe())
        let before = builder.build(access: .full, now: testNow - 9 * minute)
        let accountBefore = builder.desktopAccount
        #expect(before.plan.weekly?.usedPercent == 87)
        #expect(accountBefore == "org-b")

        try tree.writeDesktopHistory([
            orgA, orgB, HistorySample(time: testNow - 4 * minute, org: "org-a", fiveHour: 0, weekly: 100),
        ])
        let after = builder.build(access: .full, now: testNow)
        #expect(after.plan.weekly?.usedPercent == 100)
        #expect(after.plan.weekly?.source == .desktopApp)
        #expect(builder.desktopAccount == "org-a")

        #expect(MomentDetector.moments(
            previous: before, previousDesktopAccount: accountBefore,
            current: after, currentDesktopAccount: builder.desktopAccount
        ).isEmpty)
    }

    /// The same account's usage crossing a threshold is still announced.
    @Test func theSameDesktopAccountCrossingIsAnnounced() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        let orgA = HistorySample(time: testNow - 17 * hour, org: "org-a", fiveHour: 0, weekly: 100)
        let orgB = HistorySample(time: testNow - 10 * minute, org: "org-b", fiveHour: 20, weekly: 87)
        try tree.writeDesktopHistory([orgA, orgB])
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe())
        let before = builder.build(access: .full, now: testNow - 9 * minute)
        let accountBefore = builder.desktopAccount

        try tree.writeDesktopHistory([
            orgA, orgB, HistorySample(time: testNow - 4 * minute, org: "org-b", fiveHour: 22, weekly: 91),
        ])
        let after = builder.build(access: .full, now: testNow)
        #expect(builder.desktopAccount == "org-b")

        #expect(MomentDetector.moments(
            previous: before, previousDesktopAccount: accountBefore,
            current: after, currentDesktopAccount: builder.desktopAccount
        ) == [.limitCrossed(kind: .weekly, percent: 90)])
    }

    /// No desktop samples (or no access to them) = no desktop account.
    @Test func noDesktopAccountWithoutDesktopSamples() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe())
        #expect(builder.desktopAccount == nil)
        _ = builder.build(access: .full, now: testNow)
        #expect(builder.desktopAccount == nil)

        try tree.writeDesktopHistory([HistorySample(time: testNow - minute, org: "org-a", fiveHour: 5, weekly: 40)])
        _ = builder.build(access: .full, now: testNow)
        #expect(builder.desktopAccount == "org-a")

        _ = builder.build(access: AccessState(claudeDirectoryReadable: true, desktopDirectoryReadable: false), now: testNow)
        #expect(builder.desktopAccount == nil)
    }

    /// Samples with the same time: the one later in the file is the newest, as UsageKit picks the org (§2.1).
    @Test func theDesktopAccountIsTheNewestSamplesOrg() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeDesktopHistory([
            HistorySample(time: testNow - minute, org: "org-a", fiveHour: 5, weekly: 40),
            HistorySample(time: testNow - hour, org: "org-c", fiveHour: 5, weekly: 40),
            HistorySample(time: testNow - minute, org: "org-b", fiveHour: 7, weekly: 60),
        ])
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe())
        let snapshot = builder.build(access: .full, now: testNow)

        #expect(builder.desktopAccount == "org-b")
        #expect(snapshot.plan.weekly?.usedPercent == 60)
    }
}
