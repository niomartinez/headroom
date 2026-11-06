import Foundation
import HeadroomModel
import HeadroomShare
import Testing

/// The widgets get a new file when what they show changes (or on a heartbeat), and WidgetKit is asked to reload
/// them sparingly: every 10 minutes at most, or after 2 minutes, up to 6 times an hour, for urgent changes (1.1 §5.4).
@Suite struct WidgetReloadGateTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ minutes: Double) -> Date {
        start.addingTimeInterval(minutes * 60)
    }

    private func signature(weekly: Double = 40, waiting: Int = 0, idle: Int = 1, isSample: Bool = false) -> WidgetSignature {
        let plan = PlanUsage(weekly: LimitReading(
            kind: .weekly, usedPercent: weekly, resetsAt: nil, resetIsEstimated: false, observedAt: start, source: .terminal
        ))
        let sessions = (0..<waiting).map { session("n\($0)", .waitingForInput) } + (0..<idle).map { session("i\($0)", .idle) }
        return WidgetSignature(
            snapshot: HeadroomSnapshot(plan: plan, sessions: sessions, terminalBridgeConnected: true, issues: [], generatedAt: start),
            isSample: isSample, pillTool: .claude, showsSessionNames: true
        )
    }

    private func session(_ id: String, _ activity: SessionActivity) -> SessionInfo {
        SessionInfo(
            id: id, name: id, projectPath: nil, origin: .desktop, activity: activity, activitySince: nil, startedAt: nil,
            pid: nil, transcriptPath: nil, context: nil
        )
    }

    /// Runs a sequence of polls, remembering what was written the way `WidgetPublisher` does.
    private struct Run {
        var gate = WidgetReloadGate()
        var written: WidgetSignature?

        mutating func poll(_ signature: WidgetSignature, at date: Date) -> WidgetReloadGate.Decision {
            let decision = gate.decide(previous: written, current: signature, now: date)
            if decision.write { written = signature }
            return decision
        }
    }

    private typealias D = WidgetReloadGate.Decision

    @Test func theFirstPollWritesAndReloads() {
        var run = Run()
        #expect(run.poll(signature(), at: at(0)) == D(write: true, reload: true))
    }

    /// Nothing changed: nothing until the 15-minute heartbeat, which writes but doesn't reload.
    @Test func heartbeatWritesWithoutReloading() {
        var run = Run()
        _ = run.poll(signature(), at: at(0))
        #expect(run.poll(signature(), at: at(0.1)) == D(write: false, reload: false))
        #expect(run.poll(signature(), at: at(14.9)) == D(write: false, reload: false))
        #expect(run.poll(signature(), at: at(15)) == D(write: true, reload: false))
        #expect(run.poll(signature(), at: at(16)) == D(write: false, reload: false))
    }

    /// A routine change is written at once but reloaded only 10 minutes after the last reload, on a later poll.
    @Test func normalChangesReloadTenMinutesApart() {
        var run = Run()
        _ = run.poll(signature(weekly: 40), at: at(0))
        #expect(run.poll(signature(weekly: 41), at: at(3)) == D(write: true, reload: false))
        #expect(run.gate.pending == .normal)
        #expect(run.poll(signature(weekly: 41), at: at(9.9)) == D(write: false, reload: false))
        #expect(run.poll(signature(weekly: 41), at: at(10)) == D(write: false, reload: true))
        #expect(run.gate.pending == nil)
        #expect(run.poll(signature(weekly: 42), at: at(20)) == D(write: true, reload: true))
    }

    /// A limit turning amber, or someone needing you, reloads after 2 minutes.
    @Test func urgentChangesReloadTwoMinutesApart() {
        var run = Run()
        _ = run.poll(signature(weekly: 70), at: at(0))
        #expect(run.poll(signature(weekly: 76), at: at(1)) == D(write: true, reload: false))
        #expect(run.gate.pending == .urgent)
        #expect(run.poll(signature(weekly: 76), at: at(2)) == D(write: false, reload: true))
        #expect(run.poll(signature(weekly: 76, waiting: 1), at: at(4)) == D(write: true, reload: true))
        #expect(run.poll(signature(weekly: 76, waiting: 0), at: at(6)) == D(write: true, reload: true))
        // A routine change in between doesn't turn a pending urgent one into a routine one.
        #expect(run.poll(signature(weekly: 96, waiting: 0), at: at(7)) == D(write: true, reload: false))
        #expect(run.poll(signature(weekly: 97, waiting: 0), at: at(7.5)) == D(write: true, reload: false))
        #expect(run.poll(signature(weekly: 97, waiting: 0), at: at(8)) == D(write: false, reload: true))
    }

    @Test func whatCountsAsUrgent() {
        let base = signature()
        #expect(WidgetReloadGate.isUrgent(from: nil, to: base))
        #expect(!WidgetReloadGate.isUrgent(from: base, to: signature(weekly: 60)))
        #expect(WidgetReloadGate.isUrgent(from: base, to: signature(weekly: 75)))
        #expect(WidgetReloadGate.isUrgent(from: base, to: signature(waiting: 1)))
        #expect(WidgetReloadGate.isUrgent(from: base, to: signature(isSample: true)))
        #expect(!WidgetReloadGate.isUrgent(from: base, to: signature(idle: 2)))
    }

    /// At most 6 urgent reloads an hour come sooner than the normal spacing; after that urgent changes wait the
    /// normal 10 minutes, until the hour has passed.
    @Test func urgentReloadsAreCappedPerHour() {
        var run = Run()
        _ = run.poll(signature(waiting: 0), at: at(0))
        var minute = 0.0
        for index in 1...6 {
            minute += 2
            #expect(run.poll(signature(waiting: index % 2), at: at(minute)) == D(write: true, reload: true))
        }
        #expect(run.gate.urgentReloads.count == 6)
        // 14 minutes in: a seventh urgent change waits for the normal spacing (10 minutes after the reload at 12).
        #expect(run.poll(signature(waiting: 1), at: at(14)) == D(write: true, reload: false))
        #expect(run.poll(signature(waiting: 1), at: at(21.9)) == D(write: false, reload: false))
        #expect(run.poll(signature(waiting: 1), at: at(22)) == D(write: false, reload: true))
        // An hour after the first urgent reload, urgent changes may come sooner again.
        _ = run.poll(signature(waiting: 0), at: at(62.5))
        #expect(run.poll(signature(waiting: 1), at: at(64.5)) == D(write: true, reload: true))
    }

    /// Waking from sleep writes and reloads as soon as 2 minutes have passed since the last reload.
    @Test func wakeIsUrgent() {
        var run = Run()
        _ = run.poll(signature(), at: at(0))
        run.gate.noteWake()
        #expect(run.poll(signature(), at: at(1)) == D(write: true, reload: false))
        #expect(run.gate.pending == .urgent)
        #expect(run.poll(signature(), at: at(2)) == D(write: false, reload: true))
        run.gate.noteWake()
        #expect(run.poll(signature(), at: at(30)) == D(write: true, reload: true))
    }

    /// A failed write leaves nothing written: the next poll is a first write again.
    @Test func afterAFailedWriteTheNextPollWritesAgain() {
        var gate = WidgetReloadGate()
        _ = gate.decide(previous: nil, current: signature(), now: at(0))
        #expect(gate.decide(previous: nil, current: signature(), now: at(1)).write)
    }

    /// A failed write isn't tried again on every 2-second poll: a minute later, and the change stays pending.
    @Test func aFailedWriteIsTriedAgainAfterAMinute() {
        var gate = WidgetReloadGate()
        let first = gate.shouldWrite(previous: nil, current: signature(), now: at(0))
        gate.writeFailed(now: at(0))
        let soon = gate.shouldWrite(previous: nil, current: signature(), now: at(0.5))
        let almost = gate.shouldWrite(previous: nil, current: signature(), now: at(0.99))
        let pending = gate.pending
        let aMinuteLater = gate.shouldWrite(previous: nil, current: signature(), now: at(1))
        #expect(first && !soon && !almost && aMinuteLater)
        #expect(pending == .urgent)
    }

    /// A reload the gate allowed for a write that then failed isn't used up: it comes with the write that works.
    @Test func aFailedWriteUsesUpNoReload() {
        var gate = WidgetReloadGate()
        _ = gate.decide(previous: nil, current: signature(), now: at(0))
        // A normal change after 11 minutes may reload, but its write fails.
        let write = gate.shouldWrite(previous: signature(), current: signature(idle: 2), now: at(11))
        gate.writeFailed(now: at(11))
        #expect(write)
        #expect(gate.lastReloadAt == at(0))
        // The retry a minute later works, and reloads at once (not 10 minutes after the failed try).
        let retry = gate.shouldWrite(previous: nil, current: signature(idle: 2), now: at(12))
        let reload = gate.shouldReload(now: at(12))
        #expect(retry && reload)
        #expect(gate.lastReloadAt == at(12))
    }

    /// A clock set back doesn't freeze the widgets: the gate starts over.
    @Test func clockSetBack() {
        var run = Run()
        _ = run.poll(signature(weekly: 40), at: at(30))
        #expect(run.poll(signature(weekly: 41), at: at(0)) == D(write: true, reload: true))
    }
}
