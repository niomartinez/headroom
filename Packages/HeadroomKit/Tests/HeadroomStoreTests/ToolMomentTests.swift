import CodexKit
import Foundation
import HeadroomModel
import Testing
@testable import HeadroomStore

/// A snapshot with Claude tracked (a weekly reading only when given) and Codex and Copilot as given.
private func snapshot(
    at time: Date, codex: ToolUsage? = nil, copilot: ToolUsage? = nil, sessions: [SessionInfo] = [],
    claudeWeekly: LimitReading? = nil, claudeTracked: Bool = true
) -> HeadroomSnapshot {
    HeadroomSnapshot(
        plan: PlanUsage(fiveHour: nil, weekly: claudeWeekly), sessions: sessions, terminalBridgeConnected: false,
        issues: [], generatedAt: time, codex: codex, copilot: copilot, claudeTracked: claudeTracked)
}

private let earlier = testNow - 2 * second
private let observedBefore = testNow - 15 * minute
private let observedNow = testNow - minute

private func moments(from previous: HeadroomSnapshot?, to current: HeadroomSnapshot) -> [Moment] {
    MomentDetector.moments(previous: previous, current: current)
}

/// Codex: `toolLimitCrossed` per window (1.1 §6.2), with 1.0 §3.4's guards.
@Suite struct CodexLimitMomentTests {
    private func codexMoments(
        weekly: (Double?, Double?) = (nil, nil), fiveHour: (Double?, Double?) = (nil, nil),
        plans: (String?, String?) = ("Plus", "Plus"),
        observed: (Date, Date) = (observedBefore, observedNow)
    ) -> [Moment] {
        let old = codexUsage(weekly: weekly.0, fiveHour: fiveHour.0, at: observed.0, plan: plans.0)
        let new = codexUsage(weekly: weekly.1, fiveHour: fiveHour.1, at: observed.1, plan: plans.1)
        return moments(from: snapshot(at: earlier, codex: old), to: snapshot(at: testNow, codex: new))
    }

    @Test func crossingNinety() {
        #expect(codexMoments(weekly: (85, 91)) == [.toolLimitCrossed(tool: .codex, window: .weekly, percent: 90)])
        #expect(codexMoments(fiveHour: (89.5, 90)) == [.toolLimitCrossed(tool: .codex, window: .fiveHour, percent: 90)])
    }

    @Test func reachingAHundred() {
        #expect(codexMoments(weekly: (95, 100)) == [.toolLimitCrossed(tool: .codex, window: .weekly, percent: 100)])
        #expect(codexMoments(weekly: (85, 100)) == [.toolLimitCrossed(tool: .codex, window: .weekly, percent: 100)])
    }

    /// One moment per window, longest window first.
    @Test func bothWindowsCanCrossInOneStep() {
        #expect(codexMoments(weekly: (88, 90), fiveHour: (97, 101)) == [
            .toolLimitCrossed(tool: .codex, window: .weekly, percent: 90),
            .toolLimitCrossed(tool: .codex, window: .fiveHour, percent: 100),
        ])
    }

    @Test func aJumpOfMoreThanTwentyFivePointsIsACorrectionNotACrossing() {
        #expect(codexMoments(weekly: (0, 92)).isEmpty)
        #expect(codexMoments(fiveHour: (64, 90)).isEmpty)
        #expect(codexMoments(fiveHour: (65, 90)) == [.toolLimitCrossed(tool: .codex, window: .fiveHour, percent: 90)])
    }

    @Test func onlyANewObservationCanCross() {
        #expect(codexMoments(weekly: (85, 91), observed: (observedBefore, observedBefore)).isEmpty)
        #expect(codexMoments(weekly: (85, 91), observed: (observedBefore, observedBefore - minute)).isEmpty)
    }

    @Test func bothSnapshotsMustHaveTheWindow() {
        #expect(codexMoments(weekly: (nil, 95)).isEmpty)
        #expect(codexMoments(weekly: (85, nil)).isEmpty)
        // A 5-hour window that appears (Pro → Plus shape) or disappears crosses nothing.
        #expect(codexMoments(weekly: (40, 41), fiveHour: (nil, 92)).isEmpty)
    }

    @Test func stayingAboveOrFallingIsNotACrossing() {
        #expect(codexMoments(weekly: (90, 95)).isEmpty)
        #expect(codexMoments(weekly: (100, 100)).isEmpty)
        #expect(codexMoments(weekly: (95, 80)).isEmpty)
        #expect(codexMoments(weekly: (80, 89.9)).isEmpty)
    }

    /// Another plan is another account (or the same one after an upgrade): its usage crossed nothing just now.
    @Test func aPlanSwitchIsNotACrossing() {
        #expect(codexMoments(weekly: (85, 92), plans: ("Plus", "Pro")).isEmpty)
        #expect(codexMoments(weekly: (85, 92), plans: (nil, "Plus")).isEmpty)
    }

    /// No moments on the first snapshot, nor when Codex was only just tracked or isn't any more.
    @Test func codexMustBeTrackedInBothSnapshots() {
        let old = codexUsage(weekly: 85, at: observedBefore)
        let new = codexUsage(weekly: 91, at: observedNow)

        #expect(moments(from: nil, to: snapshot(at: testNow, codex: new)).isEmpty)
        #expect(moments(from: snapshot(at: earlier), to: snapshot(at: testNow, codex: new)).isEmpty)
        #expect(moments(from: snapshot(at: earlier, codex: old), to: snapshot(at: testNow)).isEmpty)
        let needsAccess = ToolUsage(tool: .codex, status: .needsAccess)
        #expect(moments(from: snapshot(at: earlier, codex: needsAccess), to: snapshot(at: testNow, codex: new)).isEmpty)
    }

    /// A window rolled over past its reset shows 0 % until the next reading, which then comes as a correction.
    @Test func aRolledOverWindowDoesNotCrossOnItsNextReading() {
        let rolled = ToolUsage(
            tool: .codex, limits: [toolLimit(.weekly, 97, at: observedBefore, resetsAt: earlier - minute)],
            status: .ok, planName: "Plus"
        ).rolledOver(now: earlier)
        let next = codexUsage(weekly: 91, at: observedNow)

        #expect(moments(from: snapshot(at: earlier, codex: rolled), to: snapshot(at: testNow, codex: next)).isEmpty)
    }

    /// Other buckets (Spark) have no moment: a moment can't name them.
    @Test func otherBucketsAreNotAnnounced() {
        func spark(_ used: Double, at date: Date) -> [NamedLimits] {
            [NamedLimits(id: "codex_spark", name: "Synthetic-Spark", limits: [toolLimit(.weekly, used, at: date)])]
        }
        let old = codexUsage(weekly: 40, at: observedBefore, otherBuckets: spark(85, at: observedBefore))
        let new = codexUsage(weekly: 41, at: observedNow, otherBuckets: spark(95, at: observedNow))

        #expect(moments(from: snapshot(at: earlier, codex: old), to: snapshot(at: testNow, codex: new)).isEmpty)
    }

    /// The Claude desktop account says nothing about Codex.
    @Test func aDesktopAccountSwitchDoesNotHideACodexCrossing() {
        let previous = snapshot(at: earlier, codex: codexUsage(weekly: 85, at: observedBefore))
        let current = snapshot(at: testNow, codex: codexUsage(weekly: 91, at: observedNow))

        #expect(MomentDetector.moments(
            previous: previous, previousDesktopAccount: "org-a", current: current, currentDesktopAccount: "org-b"
        ) == [.toolLimitCrossed(tool: .codex, window: .weekly, percent: 90)])
    }
}

/// Copilot: the monthly allowance (1.1 §6.2). Reaching 100 % is "used up" when shown.
@Suite struct CopilotLimitMomentTests {
    private func copilotMoments(
        used: (Double, Double), allowance: (Double?, Double?) = (1_500, 1_500),
        accounts: (String?, String?) = ("octo-tester", "octo-tester"), plans: (String?, String?) = ("Pro", "Pro")
    ) -> [Moment] {
        let old = copilotUsage(
            used: used.0, allowance: allowance.0, at: observedBefore, account: accounts.0, plan: plans.0)
        let new = copilotUsage(used: used.1, allowance: allowance.1, at: observedNow, account: accounts.1, plan: plans.1)
        return moments(from: snapshot(at: earlier, copilot: old), to: snapshot(at: testNow, copilot: new))
    }

    @Test func crossingNinety() {
        #expect(copilotMoments(used: (1_300, 1_380)) == [
            .toolLimitCrossed(tool: .copilot, window: .monthly, percent: 90),
        ])
    }

    @Test func reachingAHundred() {
        #expect(copilotMoments(used: (1_400, 1_500)) == [
            .toolLimitCrossed(tool: .copilot, window: .monthly, percent: 100),
        ])
        // Past the allowance Copilot keeps working on paid extra usage: no further moment.
        #expect(copilotMoments(used: (1_500, 1_620)).isEmpty)
    }

    /// "Not sure" (no allowance): no percent, so nothing to cross, however much is used.
    @Test func withoutAnAllowanceThereIsNoMoment() {
        #expect(copilotMoments(used: (1_300, 1_600), allowance: (nil, nil)).isEmpty)
        #expect(copilotMoments(used: (1_300, 1_400), allowance: (nil, 1_500)).isEmpty)
    }

    @Test func anAccountSwitchIsNotACrossing() {
        #expect(copilotMoments(used: (1_300, 1_380), accounts: ("octo-tester", "other-tester")).isEmpty)
    }

    /// Picking another plan (or editing the custom allowance) measures the same usage against another allowance.
    @Test func anAllowanceChangeIsNotACrossing() {
        #expect(copilotMoments(used: (1_300, 1_380), plans: ("Pro+", "Pro")).isEmpty)
        #expect(copilotMoments(used: (1_300, 1_310), allowance: (1_500, 1_400), plans: ("Custom", "Custom")).isEmpty)
    }

    @Test func onlyANewObservationCanCross() {
        let old = copilotUsage(used: 1_300, allowance: 1_500, at: observedBefore)
        let refetched = copilotUsage(used: 1_380, allowance: 1_500, at: observedBefore)

        #expect(moments(from: snapshot(at: earlier, copilot: old), to: snapshot(at: testNow, copilot: refetched)).isEmpty)
    }
}

@Suite struct ToolMomentOrderTests {
    /// Session moments first, then Claude's limit, then Codex's, then Copilot's.
    @Test func sessionsThenClaudeThenCodexThenCopilot() {
        let previous = snapshot(
            at: earlier,
            codex: codexUsage(weekly: 88, at: observedBefore),
            copilot: copilotUsage(used: 1_400, allowance: 1_500, at: observedBefore),
            sessions: [codexSession("t-1", .working, since: testNow - minute)],
            claudeWeekly: LimitReading(
                kind: .weekly, usedPercent: 85, resetsAt: nil, resetIsEstimated: true, observedAt: observedBefore,
                source: .terminal))
        let current = snapshot(
            at: testNow,
            codex: codexUsage(weekly: 90, at: observedNow),
            copilot: copilotUsage(used: 1_500, allowance: 1_500, at: observedNow),
            sessions: [codexSession("t-1", .idle, since: testNow - second)],
            claudeWeekly: LimitReading(
                kind: .weekly, usedPercent: 91, resetsAt: nil, resetIsEstimated: true, observedAt: observedNow,
                source: .terminal))

        #expect(moments(from: previous, to: current) == [
            .sessionFinished(sessionID: "codex:t-1", name: "ledger"),
            .limitCrossed(kind: .weekly, percent: 90),
            .toolLimitCrossed(tool: .codex, window: .weekly, percent: 90),
            .toolLimitCrossed(tool: .copilot, window: .monthly, percent: 100),
        ])
    }

    /// Claude untracked: its plan is empty, so it has no limit moments, whatever the last snapshot showed.
    @Test func untrackingClaudeIsNotACrossing() {
        let previous = snapshot(
            at: earlier,
            claudeWeekly: LimitReading(
                kind: .weekly, usedPercent: 85, resetsAt: nil, resetIsEstimated: true, observedAt: observedBefore,
                source: .terminal))
        let current = snapshot(at: testNow, codex: codexUsage(weekly: 40, at: observedNow), claudeTracked: false)

        #expect(moments(from: previous, to: current).isEmpty)
    }
}

/// Codex sessions finish when a turn completes: working → idle after at least 5 s (1.1 §6.2).
@Suite struct CodexSessionMomentTests {
    @Test func aCompletedTurnIsAFinish() {
        let previous = snapshot(at: earlier, sessions: [codexSession("t-1", .working, since: testNow - 5 * second)])
        let current = snapshot(at: testNow, sessions: [codexSession("t-1", .idle, since: testNow - second)])

        #expect(moments(from: previous, to: current) == [.sessionFinished(sessionID: "codex:t-1", name: "ledger")])
    }

    @Test func aBriefTurnIsNotAFinish() {
        let previous = snapshot(at: earlier, sessions: [codexSession("t-1", .working, since: testNow - 4 * second)])
        let current = snapshot(at: testNow, sessions: [codexSession("t-1", .idle, since: testNow - second)])

        #expect(moments(from: previous, to: current).isEmpty)
    }

    /// Through the builder: a turn seen working over two polls, then complete.
    @Test func aTurnFinishesAcrossBuilds() throws {
        let fixture = try ToolFixture()
        defer { fixture.remove() }
        let usage = codexUsage(weekly: 42, at: testNow - hour)
        let start = testNow - 30 * second
        fixture.readers.codexReading = CodexReading(
            usage: usage, sessions: [codexSession("t-1", .working, since: start)], issues: [])
        let first = fixture.build(now: testNow - 4 * second)
        let working = fixture.build(now: testNow - 2 * second)
        #expect(moments(from: first, to: working).isEmpty)

        fixture.readers.codexReading = CodexReading(
            usage: usage, sessions: [codexSession("t-1", .idle, since: testNow - second)], issues: [])
        let idle = fixture.build(now: testNow)

        #expect(moments(from: working, to: idle) == [.sessionFinished(sessionID: "codex:t-1", name: "ledger")])
    }

    /// A thread that went away (its lock released) produces nothing, like a Claude session that disappeared.
    @Test func aThreadThatDisappearedYieldsNothing() {
        let previous = snapshot(at: earlier, sessions: [codexSession("t-1", .working, since: testNow - hour)])

        #expect(moments(from: previous, to: snapshot(at: testNow)).isEmpty)
    }
}
