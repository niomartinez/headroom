import Foundation
import HeadroomModel
import HeadroomUI
import Testing

@Suite struct ChangeGateTests {
    /// What `admit` answered for each value, in order.
    private func admitted(_ values: [Int], into gate: inout ChangeGate<Int>) -> [Bool] {
        values.map { gate.admit($0) }
    }

    @Test func theFirstValueIsAlwaysAdmitted() {
        var gate = ChangeGate<Int>()
        #expect(admitted([1], into: &gate) == [true])
        #expect(gate.last == 1)
    }

    @Test func anEqualValueIsNotAdmittedAgain() {
        var gate = ChangeGate<Int>()
        #expect(admitted([1, 1, 1], into: &gate) == [true, false, false])
    }

    @Test func aChangedValueIsAdmittedAndRemembered() {
        var gate = ChangeGate<Int>()
        #expect(admitted([1, 2, 2, 1], into: &gate) == [true, true, false, true])
        #expect(gate.last == 1)
    }

    @Test func resetAdmitsTheNextValue() {
        var gate = ChangeGate<Int>()
        _ = gate.admit(1)
        gate.reset()
        #expect(gate.last == nil)
        #expect(admitted([1], into: &gate) == [true])
    }
}

/// The pill and panel are only handed a new snapshot when what they draw changed (energy): a poll
/// every 2 s produces a new snapshot (new `generatedAt`) even when nothing else changed.
@Suite struct DrawKeyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func reading(_ kind: LimitKind, _ percent: Double, age: TimeInterval = 120) -> LimitReading {
        LimitReading(
            kind: kind, usedPercent: percent, resetsAt: now.addingTimeInterval(3 * 3600), resetIsEstimated: false,
            observedAt: now.addingTimeInterval(-age), source: .desktopApp
        )
    }

    private func session(_ id: String, _ activity: SessionActivity, used: Int = 100_000) -> SessionInfo {
        SessionInfo(
            id: id, name: "Session \(id)", projectPath: "/Users/example/code/project-\(id)", origin: .desktop,
            activity: activity, activitySince: now.addingTimeInterval(-60), startedAt: now.addingTimeInterval(-3600),
            pid: nil, transcriptPath: nil,
            context: ContextUsage(usedTokens: used, windowTokens: 1_000_000, model: "claude-opus-5-5", windowIsExact: false, observedAt: nil)
        )
    }

    private func snapshot(
        plan: PlanUsage? = nil,
        sessions: [SessionInfo]? = nil,
        generatedAt: Date? = nil
    ) -> HeadroomSnapshot {
        HeadroomSnapshot(
            plan: plan ?? PlanUsage(fiveHour: reading(.fiveHour, 14), weekly: reading(.weekly, 80)),
            sessions: sessions ?? [session("a", .working), session("b", .idle)],
            terminalBridgeConnected: true,
            issues: [],
            generatedAt: generatedAt ?? now
        )
    }

    // MARK: Pill

    @Test func pillIgnoresGeneratedAt() {
        let first = PillDrawKey(snapshot: snapshot(generatedAt: now), moment: nil, now: now)
        let second = PillDrawKey(snapshot: snapshot(generatedAt: now.addingTimeInterval(2)), moment: nil, now: now.addingTimeInterval(2))
        #expect(first == second)
    }

    @Test func pillRedrawsWhenASessionStartsWorking() {
        let before = PillDrawKey(snapshot: snapshot(sessions: [session("a", .idle)]), moment: nil, now: now)
        let after = PillDrawKey(snapshot: snapshot(sessions: [session("a", .working)]), moment: nil, now: now)
        #expect(before != after)
    }

    @Test func pillRedrawsWhenALimitChanges() {
        let before = PillDrawKey(snapshot: snapshot(), moment: nil, now: now)
        let plan = PlanUsage(fiveHour: reading(.fiveHour, 14), weekly: reading(.weekly, 81))
        let after = PillDrawKey(snapshot: snapshot(plan: plan), moment: nil, now: now)
        #expect(before != after)
    }

    @Test func pillRedrawsWhenTheDataGoesStale() {
        let fresh = PillDrawKey(snapshot: snapshot(), moment: nil, now: now)
        let stale = PillDrawKey(snapshot: snapshot(), moment: nil, now: now.addingTimeInterval(PlanUsage.staleAfter))
        #expect(fresh != stale)
    }

    @Test func pillIgnoresContextChangesItDoesNotShow() {
        let before = PillDrawKey(snapshot: snapshot(sessions: [session("a", .working, used: 100_000)]), moment: nil, now: now)
        let after = PillDrawKey(snapshot: snapshot(sessions: [session("a", .working, used: 400_000)]), moment: nil, now: now)
        #expect(before == after)
    }

    @Test func pillRedrawsForEveryNewMomentEvenWithTheSameText() {
        let first = PillDrawKey(snapshot: snapshot(), moment: .sessionFinished(sessionID: "a", name: "Build"), now: now)
        let second = PillDrawKey(snapshot: snapshot(), moment: .sessionFinished(sessionID: "b", name: "Build"), now: now)
        let none = PillDrawKey(snapshot: snapshot(), moment: nil, now: now)
        #expect(first != second)
        #expect(first != none)
    }

    // MARK: Pill, 1.1 §14

    @Test func pillRedrawsWhenTheRestStateChanges() {
        let waiting = snapshot(sessions: [session("a", .waitingForInput)])
        let plain = PillDrawKey(snapshot: waiting, moment: nil, now: now)
        let resting = PillDrawKey(snapshot: waiting, moment: nil, now: now, attention: NeedsYouAttention(names: ["Session a"]))
        let two = PillDrawKey(
            snapshot: waiting, moment: nil, now: now, attention: NeedsYouAttention(names: ["Session a", "Session b"])
        )
        #expect(plain != resting)
        #expect(resting != two)
        #expect(resting.model.mode == .attention)
    }

    @Test func pillRedrawsWhenAWaitIsDismissed() {
        let waiting = snapshot(sessions: [session("a", .waitingForInput)])
        let before = PillDrawKey(snapshot: waiting, moment: nil, now: now)
        let after = PillDrawKey(snapshot: waiting, moment: nil, now: now, dismissedIDs: ["a"])
        #expect(before != after)
    }

    @Test func pillRedrawsWhenTheMenuBarHeightChanges() {
        let short = PillDrawKey(snapshot: snapshot(), moment: nil, now: now, height: 22)
        let tall = PillDrawKey(snapshot: snapshot(), moment: nil, now: now, height: 24)
        #expect(short != tall)
        #expect(short == PillDrawKey(snapshot: snapshot(), moment: nil, now: now))
    }

    // MARK: Panel

    @Test func panelIgnoresGeneratedAtAndSecondsThatDoNotChangeAnyText() {
        let first = PanelDrawKey(snapshot: snapshot(generatedAt: now), now: now)
        let second = PanelDrawKey(snapshot: snapshot(generatedAt: now.addingTimeInterval(2)), now: now.addingTimeInterval(2))
        #expect(first == second)
    }

    @Test func panelRedrawsWhenTheFooterAgeChanges() {
        let first = PanelDrawKey(snapshot: snapshot(), now: now)
        let later = PanelDrawKey(snapshot: snapshot(), now: now.addingTimeInterval(60))
        #expect(first != later)
    }

    @Test func panelRedrawsWhenContextChanges() {
        let before = PanelDrawKey(snapshot: snapshot(sessions: [session("a", .working, used: 100_000)]), now: now)
        let after = PanelDrawKey(snapshot: snapshot(sessions: [session("a", .working, used: 400_000)]), now: now)
        #expect(before != after)
    }

    @Test func panelRedrawsWhenJustFinishedChanges() {
        let idle = snapshot(sessions: [session("a", .idle)])
        #expect(PanelDrawKey(snapshot: idle, now: now) != PanelDrawKey(snapshot: idle, now: now, finishedIDs: ["a"]))
    }

    @Test func panelRedrawsWhenNeedsYouMarksChange() {
        let waiting = snapshot(sessions: [session("a", .waitingForInput), session("b", .waitingForInput)])
        let plain = PanelDrawKey(snapshot: waiting, now: now)
        #expect(plain != PanelDrawKey(snapshot: waiting, now: now, unseenIDs: ["a"]))
        #expect(plain != PanelDrawKey(snapshot: waiting, now: now, dismissedIDs: ["b"]))
    }

    /// A row that becomes a button, or whose app changed, is redrawn (1.1 §14.3).
    @Test func panelRedrawsWhenWhereARowOpensChanges() {
        let sessions = snapshot(sessions: [session("a", .working)])
        let none = PanelDrawKey(snapshot: sessions, now: now)
        let terminal = PanelDrawKey(snapshot: sessions, now: now, openTitles: ["a": "Show in Terminal"])
        let iTerm = PanelDrawKey(snapshot: sessions, now: now, openTitles: ["a": "Show in iTerm"])
        #expect(none != terminal)
        #expect(terminal != iTerm)
    }

    /// Rows hidden behind "Show N more" still count: the user can expand the list at any time.
    @Test func panelRedrawsWhenACollapsedIdleRowChanges() {
        let idle = (0..<5).map { session("i\($0)", .idle) }
        var changed = idle
        changed[4] = session("i4", .idle, used: 900_000)
        let before = PanelDrawKey(snapshot: snapshot(sessions: idle), now: now)
        let after = PanelDrawKey(snapshot: snapshot(sessions: changed), now: now)
        #expect(before != after)
    }
}
