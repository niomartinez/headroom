import Foundation
import HeadroomModel
import Testing
@testable import HeadroomStore

/// 1.1 §14.4: "needs you" stays until seen, per waiting episode; Dismiss; what the app shows and publishes.
@Suite struct NeedsYouTrackerTests {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func session(_ id: String, _ activity: SessionActivity, since: Date?) -> SessionInfo {
        SessionInfo(id: id, name: "name-\(id)", projectPath: nil, origin: .desktop, activity: activity,
                    activitySince: since, startedAt: nil, pid: nil, transcriptPath: nil, context: nil)
    }

    @Test func aNewWaitingSessionIsUnseenUntilThePanelOpens() {
        var tracker = NeedsYouTracker()
        tracker.update(sessions: [session("a", .working, since: t0)], now: t0)
        tracker.update(sessions: [session("a", .waitingForInput, since: t0 + 10)], now: t0 + 12)
        #expect(tracker.isUnseen("a"))
        tracker.markAllSeen(now: t0 + 30)
        #expect(!tracker.isUnseen("a"))
        // Still waiting on later polls: stays seen.
        tracker.update(sessions: [session("a", .waitingForInput, since: t0 + 10)], now: t0 + 60)
        #expect(!tracker.isUnseen("a"))
        #expect(tracker.seen == [.init(sessionID: "a", episodeStart: t0 + 10, at: t0 + 30)])
    }

    @Test func stoppingWaitingClearsItWithoutAClick() {
        var tracker = NeedsYouTracker()
        tracker.update(sessions: [session("a", .waitingForInput, since: t0)], now: t0)
        tracker.dismiss("a", now: t0 + 5)
        tracker.update(sessions: [session("a", .working, since: t0 + 20)], now: t0 + 20)
        #expect(!tracker.isUnseen("a"))
        #expect(tracker.episodes.isEmpty)
        #expect(tracker.dismissed.isEmpty)
    }

    @Test func aSecondEpisodeAfterWorkingIsUnseenAgain() {
        var tracker = NeedsYouTracker()
        tracker.update(sessions: [session("a", .waitingForInput, since: t0)], now: t0)
        tracker.markAllSeen(now: t0 + 5)
        tracker.update(sessions: [session("a", .working, since: t0 + 20)], now: t0 + 20)
        tracker.update(sessions: [session("a", .waitingForInput, since: t0 + 40)], now: t0 + 42)
        #expect(tracker.isUnseen("a"))
    }

    @Test func anActivitySinceBumpInsideTheSameEpisodeDoesNotReFlag() {
        var tracker = NeedsYouTracker()
        tracker.update(sessions: [session("a", .waitingForInput, since: t0)], now: t0 + 1)
        tracker.markAllSeen(now: t0 + 5)
        tracker.update(sessions: [session("a", .waitingForInput, since: t0 + 30)], now: t0 + 31)
        #expect(!tracker.isUnseen("a"))
        #expect(tracker.episodes["a"] == t0)
    }

    @Test func aRelaunchKeepsWhatWasSeenAndDismissed() throws {
        var before = NeedsYouTracker()
        before.update(sessions: [session("a", .waitingForInput, since: t0), session("b", .waitingForInput, since: t0)],
                      now: t0 + 1)
        before.markAllSeen(now: t0 + 5)
        before.dismiss("b", now: t0 + 6)
        let saved = try JSONEncoder().encode(before)

        // Persisted marks, fresh episodes: the first sighting is the relaunch, activitySince is older.
        var after = try JSONDecoder().decode(NeedsYouTracker.self, from: saved)
        #expect(after.episodes.isEmpty)
        after.update(sessions: [session("a", .waitingForInput, since: t0), session("b", .waitingForInput, since: t0)],
                     now: t0 + 3600)
        #expect(!after.isUnseen("a"))
        #expect(after.isDismissed("b"))

        // Waiting that started while Headroom was quit is new.
        var later = try JSONDecoder().decode(NeedsYouTracker.self, from: saved)
        later.update(sessions: [session("a", .waitingForInput, since: t0 + 600)], now: t0 + 3600)
        #expect(later.isUnseen("a"))
        // a's mark belonged to the earlier episode; b isn't listed, so its mark stays.
        #expect(later.seen.map(\.sessionID) == ["b"])
    }

    @Test func dismissMutesOnlyThisEpisode() {
        var tracker = NeedsYouTracker()
        tracker.update(sessions: [session("a", .waitingForInput, since: t0), session("b", .waitingForInput, since: t0)], now: t0)
        tracker.dismiss("a", now: t0 + 5)
        #expect(tracker.isDismissed("a"))
        #expect(!tracker.isUnseen("a"))
        #expect(tracker.isUnseen("b"))
        #expect(tracker.dismissedIDs == ["a"])
        tracker.update(sessions: [session("a", .idle, since: t0 + 20), session("b", .waitingForInput, since: t0)], now: t0 + 20)
        tracker.update(sessions: [session("a", .waitingForInput, since: t0 + 40), session("b", .waitingForInput, since: t0)], now: t0 + 40)
        #expect(!tracker.isDismissed("a"))
        #expect(tracker.isUnseen("a"))
    }

    @Test func undoBringsTheRowBack() {
        var tracker = NeedsYouTracker()
        tracker.update(sessions: [session("a", .waitingForInput, since: t0)], now: t0)
        tracker.markAllSeen(now: t0 + 1)
        tracker.dismiss("a", now: t0 + 2)
        tracker.undoDismiss("a")
        #expect(!tracker.isDismissed("a"))
        // It was seen before it was dismissed: no rest state again.
        #expect(!tracker.isUnseen("a"))
    }

    @Test func onlyWaitingSessionsCanBeDismissed() {
        var tracker = NeedsYouTracker()
        tracker.update(sessions: [session("a", .working, since: t0)], now: t0)
        tracker.dismiss("a", now: t0 + 1)
        tracker.dismiss("missing", now: t0 + 1)
        #expect(tracker.dismissed.isEmpty)
    }

    @Test func sessionsMissingFromASnapshotKeepTheirMarks() {
        var tracker = NeedsYouTracker()
        tracker.update(sessions: [session("a", .waitingForInput, since: t0)], now: t0)
        tracker.dismiss("a", now: t0 + 1)
        tracker.update(sessions: [], now: t0 + 2) // e.g. the registry couldn't be read
        #expect(tracker.dismissed.map(\.sessionID) == ["a"])
        tracker.update(sessions: [session("a", .waitingForInput, since: t0)], now: t0 + 4)
        #expect(tracker.isDismissed("a"))
        tracker.update(sessions: [], now: t0 + NeedsYouTracker.retention + 10)
        #expect(tracker.dismissed.isEmpty)
    }

    /// Marks are kept a week, even for a session that waits all that time.
    @Test func marksExpireAfterAWeek() {
        var tracker = NeedsYouTracker()
        tracker.update(sessions: [session("a", .waitingForInput, since: t0)], now: t0)
        tracker.markAllSeen(now: t0 + 1)
        tracker.update(sessions: [session("a", .waitingForInput, since: t0)], now: t0 + NeedsYouTracker.retention - 60)
        #expect(!tracker.isUnseen("a"))
        tracker.update(sessions: [session("a", .waitingForInput, since: t0)], now: t0 + NeedsYouTracker.retention + 60)
        #expect(tracker.seen.isEmpty)
    }

    @Test func unseenKeepsDisplayOrder() {
        var tracker = NeedsYouTracker()
        let sessions = [session("w", .working, since: t0), session("b", .waitingForInput, since: t0 + 9),
                        session("a", .waitingForInput, since: t0 + 3)]
        tracker.update(sessions: sessions, now: t0 + 10)
        #expect(tracker.unseen(in: sessions).map(\.id) == ["b", "a"])
    }

    @Test func sessionsWithoutATimeStartTheirEpisodeWhenFirstSeen() {
        var tracker = NeedsYouTracker()
        tracker.update(sessions: [session("a", .waitingForInput, since: nil)], now: t0)
        tracker.update(sessions: [session("a", .waitingForInput, since: nil)], now: t0 + 2)
        #expect(tracker.episodes["a"] == t0)
    }

    // MARK: Presentation

    private func snapshot(_ sessions: [SessionInfo]) -> HeadroomSnapshot {
        var snapshot = HeadroomSnapshot.empty(at: t0)
        snapshot.sessions = sessions.sortedForDisplay()
        return snapshot
    }

    @Test func dismissedWaitsReadAsIdleAndLeaveTheCounts() {
        let raw = snapshot([session("w", .working, since: t0 - 60), session("a", .waitingForInput, since: t0 - 120),
                            session("stale", .waitingForInput, since: t0 - 11_400), session("i", .idle, since: t0 - 1800)])
        var tracker = NeedsYouTracker()
        tracker.update(sessions: raw.sessions, now: t0)
        tracker.dismiss("stale", now: t0 + 1)

        let shown = tracker.presentation(of: raw)
        #expect(shown.dismissedIDs == ["stale"])
        #expect(shown.snapshot.waitingCount == 1)
        #expect(shown.snapshot.activeCount == 2)
        #expect(shown.snapshot.sessions.map(\.id) == ["w", "a", "i", "stale"])
        #expect(shown.snapshot.sessions.last?.activity == .idle)
        #expect(shown.unseen.map(\.id) == ["a"])
        #expect(shown.unseenNames == ["name-a"])
        #expect(shown.unseenIDs == ["a"])
    }

    @Test func nothingDismissedLeavesTheSnapshotAlone() {
        let raw = snapshot([session("a", .waitingForInput, since: t0), session("w", .working, since: t0)])
        var tracker = NeedsYouTracker()
        tracker.update(sessions: raw.sessions, now: t0)
        #expect(tracker.presentation(of: raw).snapshot == raw)
        #expect(raw.applyingDismissals(["w"]) == raw)
    }

    @Test func seenSessionsLeaveTheRestState() {
        let raw = snapshot([session("a", .waitingForInput, since: t0), session("b", .waitingForInput, since: t0 + 1)])
        var tracker = NeedsYouTracker()
        tracker.update(sessions: raw.sessions, now: t0 + 2)
        #expect(tracker.presentation(of: raw).unseen.count == 2)
        tracker.markAllSeen(now: t0 + 3)
        #expect(tracker.presentation(of: raw).unseen.isEmpty)
        #expect(tracker.presentation(of: raw).snapshot.waitingCount == 2)
    }
}
