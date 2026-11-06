import Foundation
import HeadroomModel
import HeadroomStore
import HeadroomUI
import Testing

/// "Needs you" stays until seen, the app's side (1.1 §14.4): the rest state, the panel's hold and wash, Dismiss, the
/// setting, and the marks saved across launches.
@Suite struct NeedsYouStateTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A fresh defaults domain with the app's defaults registered; removed by the caller.
    private func makeDefaults() -> (UserDefaults, String) {
        let name = "HeadroomNeedsYouStateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        Preferences.registerDefaults(in: defaults)
        return (defaults, name)
    }

    private func session(_ id: String, _ activity: SessionActivity, since: TimeInterval = -60) -> SessionInfo {
        SessionInfo(
            id: id, name: "Session \(id)", projectPath: nil, origin: .desktop, activity: activity,
            activitySince: now.addingTimeInterval(since), startedAt: now.addingTimeInterval(-3600), pid: nil,
            transcriptPath: nil, context: nil
        )
    }

    private func snapshot(_ sessions: [SessionInfo]) -> HeadroomSnapshot {
        HeadroomSnapshot(plan: .empty, sessions: sessions, terminalBridgeConnected: false, issues: [], generatedAt: now)
    }

    /// The pill's rest state for `sessions` with moments on and real data.
    private func attention(_ state: NeedsYouState, _ sessions: [SessionInfo]) -> NeedsYouAttention? {
        state.pillAttention(state.presentation(of: snapshot(sessions), sampleData: false), showsMoments: true, sampleData: false)
    }

    @Test func keepingNeedsYouIsOnByDefault() {
        let (defaults, name) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        #expect(defaults.bool(forKey: Preferences.keepNeedsYou))
        #expect(NeedsYouState(defaults: defaults).keepsInMenuBar)
    }

    @Test func anUnseenWaitRestsInThePill() {
        let (defaults, name) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        var state = NeedsYouState(defaults: defaults)
        let sessions = [session("a", .waitingForInput), session("b", .working)]
        state.update(sessions: sessions, now: now)
        #expect(attention(state, sessions)?.names == ["Session a"])
    }

    /// Opening the panel marks the wait seen, but the pill keeps "(!) harbor" until the panel closes, then narrows.
    @Test func thePanelHoldsTheRestStateUntilItCloses() {
        let (defaults, name) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        var state = NeedsYouState(defaults: defaults)
        let sessions = [session("a", .waitingForInput)]
        state.update(sessions: sessions, now: now)
        let shown = attention(state, sessions)

        let seen = state.panelOpened(attention: shown, sampleData: false, now: now)
        #expect(seen == ["a"])
        #expect(state.panelUnseenIDs == ["a"])
        #expect(attention(state, sessions) == shown)
        #expect(!state.tracker.isUnseen("a"))

        state.panelClosed()
        #expect(attention(state, sessions) == nil)
        #expect(state.panelUnseenIDs.isEmpty)
    }

    /// A wait that begins while the panel is open is seen there, and gets the wash too.
    @Test func aWaitThatBeginsWhileThePanelIsOpenIsSeen() {
        let (defaults, name) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        var state = NeedsYouState(defaults: defaults)
        state.update(sessions: [session("a", .working)], now: now)
        let seen = state.panelOpened(attention: nil, sampleData: false, now: now)
        #expect(seen.isEmpty)

        let waiting = [session("a", .waitingForInput, since: 1)]
        state.update(sessions: waiting, now: now.addingTimeInterval(2))
        #expect(state.panelUnseenIDs == ["a"])
        state.panelClosed()
        #expect(attention(state, waiting) == nil)
    }

    @Test func aNewWaitAlertsAgain() {
        let (defaults, name) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        var state = NeedsYouState(defaults: defaults)
        state.update(sessions: [session("a", .waitingForInput)], now: now)
        _ = state.panelOpened(attention: nil, sampleData: false, now: now)
        state.panelClosed()

        state.update(sessions: [session("a", .working, since: 10)], now: now.addingTimeInterval(10))
        let again = [session("a", .waitingForInput, since: 20)]
        state.update(sessions: again, now: now.addingTimeInterval(20))
        #expect(attention(state, again)?.names == ["Session a"])
    }

    /// Seen and dismissed waits survive a relaunch: a new `NeedsYouState` on the same defaults doesn't nag.
    @Test func marksPersistAcrossLaunches() {
        let (defaults, name) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let sessions = [session("a", .waitingForInput, since: -600), session("b", .waitingForInput, since: -600)]
        var first = NeedsYouState(defaults: defaults)
        first.update(sessions: sessions, now: now)
        first.dismiss("b", now: now)
        _ = first.panelOpened(attention: nil, sampleData: false, now: now)
        first.panelClosed()

        var relaunched = NeedsYouState(defaults: defaults)
        #expect(relaunched.tracker.seen == first.tracker.seen)
        #expect(relaunched.tracker.dismissed == first.tracker.dismissed)
        relaunched.update(sessions: sessions, now: now.addingTimeInterval(3600))
        #expect(attention(relaunched, sessions) == nil)
        #expect(relaunched.tracker.dismissedIDs == ["b"])
    }

    /// `--render-live` reads the marks but must not write the menu bar app's settings.
    @Test func aStateThatDoesNotPersistNeverWrites() {
        let (defaults, name) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        var state = NeedsYouState(defaults: defaults, persists: false)
        state.update(sessions: [session("a", .waitingForInput)], now: now)
        state.dismiss("a", now: now)
        state.setKeepsInMenuBar(false)
        #expect(defaults.object(forKey: Preferences.needsYouDismissed) == nil)
        #expect(defaults.bool(forKey: Preferences.keepNeedsYou))
    }

    /// Dismissed waits read as idle everywhere the snapshot is shown, and leave the rest state.
    @Test func dismissTakesTheWaitOutOfThePresentation() {
        let (defaults, name) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        var state = NeedsYouState(defaults: defaults)
        let sessions = [session("a", .waitingForInput), session("b", .waitingForInput)]
        state.update(sessions: sessions, now: now)
        let dismissed = state.dismiss("a", now: now)
        let dismissedMissing = state.dismiss("missing", now: now)
        #expect(dismissed)
        #expect(!dismissedMissing)

        let presentation = state.presentation(of: snapshot(sessions), sampleData: false)
        #expect(presentation.dismissedIDs == ["a"])
        #expect(presentation.snapshot.waitingCount == 1)
        #expect(presentation.snapshot.sessions.first { $0.id == "a" }?.activity == .idle)
        #expect(attention(state, sessions)?.names == ["Session b"])

        let undone = state.undoDismiss("a")
        #expect(undone)
        #expect(state.presentation(of: snapshot(sessions), sampleData: false).snapshot.waitingCount == 2)
    }

    @Test func noRestStateInSampleDataWithMomentsOffOrWithTheSettingOff() {
        let (defaults, name) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        var state = NeedsYouState(defaults: defaults)
        let sessions = [session("a", .waitingForInput)]
        state.update(sessions: sessions, now: now)
        let presentation = state.presentation(of: snapshot(sessions), sampleData: false)
        #expect(state.pillAttention(presentation, showsMoments: true, sampleData: true) == nil)
        #expect(state.pillAttention(presentation, showsMoments: false, sampleData: false) == nil)

        state.setKeepsInMenuBar(false)
        #expect(state.pillAttention(presentation, showsMoments: true, sampleData: false) == nil)
        #expect(!defaults.bool(forKey: Preferences.keepNeedsYou))
        #expect(!NeedsYouState(defaults: defaults).keepsInMenuBar)
    }

    /// Sample sessions are shown as they are, and opening the panel over them marks no real wait seen.
    @Test func sampleDataIsShownAsItIsAndMarksNothing() {
        let (defaults, name) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        var state = NeedsYouState(defaults: defaults)
        let sessions = [session("a", .waitingForInput)]
        state.update(sessions: sessions, now: now)
        state.dismiss("a", now: now)
        #expect(state.presentation(of: snapshot(sessions), sampleData: true).snapshot.waitingCount == 1)

        state.undoDismiss("a")
        let seen = state.panelOpened(attention: nil, sampleData: true, now: now)
        #expect(seen.isEmpty)
        #expect(state.tracker.isUnseen("a"))
    }
}

/// The marks as UserDefaults stores them: session ids and times only.
@Suite struct NeedsYouMarksTests {
    private let mark = NeedsYouTracker.Mark(
        sessionID: "a", episodeStart: Date(timeIntervalSince1970: 1_800_000_000), at: Date(timeIntervalSince1970: 1_800_000_060)
    )

    @Test func marksRoundTrip() {
        #expect(NeedsYouMarks.decode(NeedsYouMarks.encode([mark])) == [mark])
    }

    @Test func malformedEntriesAreSkipped() {
        let stored: [Any] = [
            "not a dictionary",
            ["session": "", "episodeStart": 1.0, "at": 2.0],
            ["session": "b", "at": 2.0],
            ["session": "c", "episodeStart": "soon", "at": 2.0],
        ] + NeedsYouMarks.encode([mark])
        #expect(NeedsYouMarks.decode(stored) == [mark])
        #expect(NeedsYouMarks.decode(nil).isEmpty)
    }

    @Test func onlyIdsAndTimesAreStored() {
        let stored = NeedsYouMarks.encode([mark])
        #expect(stored.count == 1)
        #expect(Set(stored[0].keys) == ["session", "episodeStart", "at"])
    }
}

/// 1.1.1: Just finished's saved marks.
@Suite struct FinishedMarksTests {
    private let marks = ["a": Date(timeIntervalSince1970: 1_800_000_060)]

    @Test func marksRoundTrip() {
        #expect(FinishedMarks.decode(FinishedMarks.encode(marks)) == marks)
    }

    @Test func malformedEntriesAreSkipped() {
        let stored: [String: Any] = ["": 1.0, "b": "soon", "c": Double.nan, "a": 1_800_000_060.0]
        #expect(FinishedMarks.decode(stored) == marks)
        #expect(FinishedMarks.decode(nil).isEmpty)
    }
}
