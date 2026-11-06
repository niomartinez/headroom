import Foundation
import HeadroomModel
import Testing
@testable import HeadroomStore

private func session(_ id: String, _ activity: SessionActivity, since: Date?, name: String = "Polish onboarding copy") -> SessionInfo {
    SessionInfo(
        id: id, name: name, projectPath: "/Users/tester/code/sample-app", origin: .desktop, activity: activity,
        activitySince: since, startedAt: nil, pid: 100, transcriptPath: nil, context: nil)
}

private func reading(
    _ kind: LimitKind, _ used: Double, at observedAt: Date, source: ReadingSource = .desktopApp
) -> LimitReading {
    LimitReading(kind: kind, usedPercent: used, resetsAt: nil, resetIsEstimated: true, observedAt: observedAt, source: source)
}

private func snapshot(
    at time: Date,
    sessions: [SessionInfo] = [],
    fiveHour: LimitReading? = nil,
    weekly: LimitReading? = nil
) -> HeadroomSnapshot {
    HeadroomSnapshot(
        plan: PlanUsage(fiveHour: fiveHour, weekly: weekly), sessions: sessions,
        terminalBridgeConnected: false, issues: [], generatedAt: time)
}

private let earlier = testNow - 2 * second

@Suite struct MomentDetectorSessionTests {
    @Test func noMomentsOnTheFirstSnapshot() {
        let current = snapshot(
            at: testNow,
            sessions: [session("a", .waitingForInput, since: testNow - minute), session("b", .idle, since: testNow)],
            weekly: reading(.weekly, 95, at: testNow))

        #expect(MomentDetector.moments(previous: nil, current: current).isEmpty)
    }

    @Test func sessionFinishedAfterWorkingLongEnough() {
        let previous = snapshot(at: earlier, sessions: [session("a", .working, since: testNow - 5 * second)])
        let current = snapshot(at: testNow, sessions: [session("a", .idle, since: testNow, name: "Renamed")])

        #expect(MomentDetector.moments(previous: previous, current: current) == [
            .sessionFinished(sessionID: "a", name: "Renamed"),
        ])
    }

    @Test func noSessionFinishedAfterABriefBurstOfWork() {
        let previous = snapshot(at: earlier, sessions: [session("a", .working, since: testNow - 4 * second)])
        let current = snapshot(at: testNow, sessions: [session("a", .idle, since: testNow)])

        #expect(MomentDetector.moments(previous: previous, current: current).isEmpty)
    }

    @Test func workingWithoutAKnownStartCountsAsLongEnough() {
        let previous = snapshot(at: earlier, sessions: [session("a", .working, since: nil)])
        let current = snapshot(at: testNow, sessions: [session("a", .idle, since: testNow)])

        #expect(MomentDetector.moments(previous: previous, current: current) == [
            .sessionFinished(sessionID: "a", name: "Polish onboarding copy"),
        ])
    }

    @Test func onlyWorkingToIdleIsAFinish() {
        let previous = snapshot(at: earlier, sessions: [
            session("waiting", .waitingForInput, since: testNow - hour),
            session("idle", .idle, since: testNow - hour),
            session("still", .working, since: testNow - hour),
        ])
        let current = snapshot(at: testNow, sessions: [
            session("waiting", .idle, since: testNow),
            session("idle", .idle, since: testNow),
            session("still", .working, since: testNow - hour),
        ])

        #expect(MomentDetector.moments(previous: previous, current: current).isEmpty)
    }

    @Test func sessionNeedsInputWhenItStartsWaiting() {
        let previous = snapshot(at: earlier, sessions: [
            session("from-working", .working, since: testNow - 2 * second),
            session("from-idle", .idle, since: testNow - hour),
        ])
        let current = snapshot(at: testNow, sessions: [
            session("from-working", .waitingForInput, since: testNow),
            session("from-idle", .waitingForInput, since: testNow),
        ])

        #expect(Set(MomentDetector.moments(previous: previous, current: current)) == [
            .sessionNeedsInput(sessionID: "from-working", name: "Polish onboarding copy"),
            .sessionNeedsInput(sessionID: "from-idle", name: "Polish onboarding copy"),
        ])
    }

    @Test func stillWaitingIsNotAnotherMoment() {
        let previous = snapshot(at: earlier, sessions: [session("a", .waitingForInput, since: testNow - minute)])
        let current = snapshot(at: testNow, sessions: [session("a", .waitingForInput, since: testNow)])

        #expect(MomentDetector.moments(previous: previous, current: current).isEmpty)
    }

    @Test func newSessionsAreNotMoments() {
        let previous = snapshot(at: earlier)
        let current = snapshot(at: testNow, sessions: [
            session("new-waiting", .waitingForInput, since: testNow),
            session("new-idle", .idle, since: testNow),
        ])

        #expect(MomentDetector.moments(previous: previous, current: current).isEmpty)
    }

    @Test func aSessionThatDisappearedYieldsNothing() {
        let previous = snapshot(at: earlier, sessions: [
            session("gone-working", .working, since: testNow - hour),
            session("gone-waiting", .waitingForInput, since: testNow - hour),
        ])
        let current = snapshot(at: testNow)

        #expect(MomentDetector.moments(previous: previous, current: current).isEmpty)
    }
}

@Suite struct MomentDetectorLimitTests {
    private func moments(
        _ kind: LimitKind,
        from previousUsed: Double?,
        to currentUsed: Double?,
        previousObserved: Date = testNow - 15 * minute,
        currentObserved: Date = testNow - minute
    ) -> [Moment] {
        let previousReading = previousUsed.map { reading(kind, $0, at: previousObserved) }
        let currentReading = currentUsed.map { reading(kind, $0, at: currentObserved) }
        let previous = kind == .weekly
            ? snapshot(at: earlier, weekly: previousReading)
            : snapshot(at: earlier, fiveHour: previousReading)
        let current = kind == .weekly
            ? snapshot(at: testNow, weekly: currentReading)
            : snapshot(at: testNow, fiveHour: currentReading)
        return MomentDetector.moments(previous: previous, current: current)
    }

    @Test(arguments: LimitKind.allCases)
    func crossingNinety(kind: LimitKind) {
        #expect(moments(kind, from: 85, to: 90) == [.limitCrossed(kind: kind, percent: 90)])
        #expect(moments(kind, from: 89.5, to: 97) == [.limitCrossed(kind: kind, percent: 90)])
    }

    @Test(arguments: LimitKind.allCases)
    func reachingAHundred(kind: LimitKind) {
        #expect(moments(kind, from: 95, to: 100) == [.limitCrossed(kind: kind, percent: 100)])
        #expect(moments(kind, from: 99, to: 104) == [.limitCrossed(kind: kind, percent: 100)])
    }

    @Test func crossingBothThresholdsAtOnceIsOneMomentForTheHigher() {
        #expect(moments(.weekly, from: 85, to: 100) == [.limitCrossed(kind: .weekly, percent: 100)])
    }

    @Test func aJumpOfMoreThanTwentyFivePointsIsACorrectionNotACrossing() {
        #expect(moments(.weekly, from: 0, to: 92).isEmpty)
        #expect(moments(.weekly, from: 70, to: 100).isEmpty)
        #expect(moments(.fiveHour, from: 64, to: 90).isEmpty)
        // Exactly 25 points still counts.
        #expect(moments(.fiveHour, from: 65, to: 90) == [.limitCrossed(kind: .fiveHour, percent: 90)])
    }

    @Test func onlyANewObservationCanCross() {
        let same = testNow - 15 * minute
        #expect(moments(.weekly, from: 85, to: 91, previousObserved: same, currentObserved: same).isEmpty)
        #expect(moments(.weekly, from: 85, to: 91, previousObserved: same, currentObserved: same - minute).isEmpty)
    }

    @Test func bothReadingsMustExist() {
        #expect(moments(.weekly, from: nil, to: 95).isEmpty)
        #expect(moments(.weekly, from: 85, to: nil).isEmpty)
    }

    @Test func stayingAboveOrFallingIsNotACrossing() {
        #expect(moments(.weekly, from: 90, to: 95).isEmpty)
        #expect(moments(.weekly, from: 100, to: 100).isEmpty)
        #expect(moments(.weekly, from: 95, to: 80).isEmpty)
        #expect(moments(.weekly, from: 80, to: 89.9).isEmpty)
    }

    @Test func bothLimitsCanCrossInOneStep() {
        let previous = snapshot(
            at: earlier,
            fiveHour: reading(.fiveHour, 88, at: testNow - 15 * minute),
            weekly: reading(.weekly, 98, at: testNow - 15 * minute))
        let current = snapshot(
            at: testNow,
            fiveHour: reading(.fiveHour, 91, at: testNow - minute),
            weekly: reading(.weekly, 100, at: testNow - minute))

        #expect(MomentDetector.moments(previous: previous, current: current) == [
            .limitCrossed(kind: .fiveHour, percent: 90),
            .limitCrossed(kind: .weekly, percent: 100),
        ])
    }

    @Test func sessionMomentsComeBeforeLimitMoments() {
        let previous = snapshot(
            at: earlier, sessions: [session("a", .working, since: testNow - hour)],
            weekly: reading(.weekly, 88, at: testNow - 15 * minute))
        let current = snapshot(
            at: testNow, sessions: [session("a", .idle, since: testNow)],
            weekly: reading(.weekly, 90, at: testNow - minute))

        #expect(MomentDetector.moments(previous: previous, current: current) == [
            .sessionFinished(sessionID: "a", name: "Polish onboarding copy"),
            .limitCrossed(kind: .weekly, percent: 90),
        ])
    }
}

/// Switching accounts in the desktop app (spec §2.1: "Several orgs can appear") swaps in the other account's
/// usage. That is not usage crossing a threshold, even when it is higher by less than the 25-point guard.
@Suite struct MomentDetectorAccountTests {
    private func moments(
        _ kind: LimitKind,
        from previousUsed: Double,
        account previousAccount: String?,
        to currentUsed: Double,
        account currentAccount: String?,
        source: ReadingSource = .desktopApp
    ) -> [Moment] {
        let old = reading(kind, previousUsed, at: testNow - 15 * minute, source: source)
        let new = reading(kind, currentUsed, at: testNow - minute, source: source)
        let previous = kind == .weekly ? snapshot(at: earlier, weekly: old) : snapshot(at: earlier, fiveHour: old)
        let current = kind == .weekly ? snapshot(at: testNow, weekly: new) : snapshot(at: testNow, fiveHour: new)
        return MomentDetector.moments(
            previous: previous, previousDesktopAccount: previousAccount,
            current: current, currentDesktopAccount: currentAccount)
    }

    /// The real case (2026-09-22): one org at 87 % weekly, then the app switched to an org that had been at 100 %
    /// for 17 hours. Without the guard the pill announced "Weekly limit reached".
    @Test(arguments: LimitKind.allCases)
    func aDesktopAccountSwitchIsNotACrossing(kind: LimitKind) {
        #expect(moments(kind, from: 87, account: "org-b83b", to: 100, account: "org-abc4").isEmpty)
        #expect(moments(kind, from: 85, account: "org-b83b", to: 92, account: "org-abc4").isEmpty)
    }

    @Test(arguments: LimitKind.allCases)
    func theSameDesktopAccountStillCrosses(kind: LimitKind) {
        #expect(moments(kind, from: 87, account: "org-b83b", to: 100, account: "org-b83b") == [
            .limitCrossed(kind: kind, percent: 100),
        ])
        #expect(moments(kind, from: 85, account: "org-b83b", to: 92, account: "org-b83b") == [
            .limitCrossed(kind: kind, percent: 90),
        ])
    }

    /// Nil = the caller doesn't know that account: compared as before, like `moments(previous:current:)`.
    @Test func anUnknownAccountIsComparedAsBefore() {
        #expect(moments(.weekly, from: 87, account: nil, to: 100, account: "org-abc4") == [
            .limitCrossed(kind: .weekly, percent: 100),
        ])
        #expect(moments(.weekly, from: 87, account: "org-b83b", to: 100, account: nil) == [
            .limitCrossed(kind: .weekly, percent: 100),
        ])
        #expect(moments(.weekly, from: 87, account: nil, to: 100, account: nil) == [
            .limitCrossed(kind: .weekly, percent: 100),
        ])
    }

    /// The desktop account says nothing about terminal readings (spec §2.4 carries no account).
    @Test func terminalReadingsAreComparedWhateverTheDesktopAccount() {
        #expect(moments(.weekly, from: 85, account: "org-b83b", to: 91, account: "org-abc4", source: .terminal) == [
            .limitCrossed(kind: .weekly, percent: 90),
        ])
    }

    /// Session moments don't depend on the account.
    @Test func sessionMomentsSurviveAnAccountSwitch() {
        let previous = snapshot(
            at: earlier, sessions: [session("a", .working, since: testNow - hour)],
            weekly: reading(.weekly, 87, at: testNow - 15 * minute))
        let current = snapshot(
            at: testNow, sessions: [session("a", .idle, since: testNow)],
            weekly: reading(.weekly, 100, at: testNow - minute))

        #expect(MomentDetector.moments(
            previous: previous, previousDesktopAccount: "org-b83b",
            current: current, currentDesktopAccount: "org-abc4"
        ) == [.sessionFinished(sessionID: "a", name: "Polish onboarding copy")])
    }

    @Test func noMomentsWithoutAPreviousSnapshot() {
        let current = snapshot(at: testNow, weekly: reading(.weekly, 100, at: testNow - minute))

        #expect(MomentDetector.moments(
            previous: nil, previousDesktopAccount: nil, current: current, currentDesktopAccount: "org-abc4"
        ).isEmpty)
    }
}
