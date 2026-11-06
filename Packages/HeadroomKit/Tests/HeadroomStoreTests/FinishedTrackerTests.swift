import Foundation
import HeadroomModel
import Testing
@testable import HeadroomStore

/// 1.1.1: "Just finished" stays until the user reviews the session, or it works or waits again.
@Suite struct FinishedTrackerTests {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func session(_ id: String, _ activity: SessionActivity) -> SessionInfo {
        SessionInfo(id: id, name: "name-\(id)", projectPath: nil, origin: .desktop, activity: activity,
                    activitySince: t0, startedAt: nil, pid: nil, transcriptPath: nil, context: nil)
    }

    func finish(_ id: String) -> Moment { .sessionFinished(sessionID: id, name: "name-\(id)") }

    @Test func aFinishStaysUntilReviewed() {
        var tracker = FinishedTracker()
        tracker.update(sessions: [session("a", .idle), session("b", .idle)], moments: [finish("a")], now: t0)
        #expect(tracker.ids(in: [session("a", .idle), session("b", .idle)]) == ["a"])
        // Later polls without a moment keep it.
        tracker.update(sessions: [session("a", .idle)], moments: [], now: t0 + 3_600)
        #expect(tracker.ids(in: [session("a", .idle)]) == ["a"])
        let reviewed = tracker.review("a")
        let reviewedAgain = tracker.review("a")
        #expect(reviewed && !reviewedAgain)
        #expect(tracker.ids(in: [session("a", .idle)]).isEmpty)
    }

    @Test func workingOrWaitingAgainEndsIt() {
        var tracker = FinishedTracker()
        tracker.update(sessions: [session("a", .idle), session("b", .idle)], moments: [finish("a"), finish("b")], now: t0)
        tracker.update(sessions: [session("a", .working), session("b", .waitingForInput)], moments: [], now: t0 + 10)
        #expect(tracker.finished.isEmpty)
    }

    /// An unreadable registry lists nothing: the marks wait, until `retention`.
    @Test func unlistedSessionsKeepTheirMarkUntilRetention() {
        var tracker = FinishedTracker()
        tracker.update(sessions: [session("a", .idle)], moments: [finish("a")], now: t0)
        tracker.update(sessions: [], moments: [], now: t0 + 60)
        #expect(tracker.finished == ["a": t0])
        tracker.update(sessions: [], moments: [], now: t0 + FinishedTracker.retention + 1)
        #expect(tracker.finished.isEmpty)
    }

    @Test func clearReviewsEverything() {
        var tracker = FinishedTracker(finished: ["a": t0, "b": t0])
        let cleared = tracker.reviewAll()
        #expect(cleared && tracker.finished.isEmpty)
        let clearedAgain = tracker.reviewAll()
        #expect(!clearedAgain)
    }

    @Test func otherMomentsMarkNothing() {
        var tracker = FinishedTracker()
        tracker.update(
            sessions: [session("a", .waitingForInput)],
            moments: [.sessionNeedsInput(sessionID: "a", name: "name-a"), .limitCrossed(kind: .weekly, percent: 90)],
            now: t0
        )
        #expect(tracker.finished.isEmpty)
    }

    // MARK: Looked at in its own app (1.1.2)

    func app(_ id: String, _ tool: ToolID, origin: SessionOrigin = .desktop, desktopID: String? = nil) -> SessionInfo {
        SessionInfo(id: id, name: "name-\(id)", projectPath: nil, origin: origin, activity: .idle, activitySince: t0,
                    startedAt: nil, pid: nil, transcriptPath: nil, context: nil, tool: tool, desktopSessionID: desktopID)
    }

    func finishedTracker(_ ids: String...) -> FinishedTracker {
        FinishedTracker(finished: Dictionary(uniqueKeysWithValues: ids.map { ($0, t0) }))
    }

    @Test func aClaudeSessionOpenedInTheClaudeAppAfterItFinishedIsViewed() {
        let sessions = [app("a", .claude, desktopID: "local_a"), app("b", .claude, desktopID: "local_b")]
        var tracker = finishedTracker("a", "b")
        let signals = SessionViewSignals(claudeFocusedAt: ["local_a": t0 + 30, "local_b": t0 - 600])
        tracker.reviewViewed(sessions: sessions, signals: signals, frontmost: "com.apple.Terminal", hostBundleID: { _ in nil }, now: t0 + 40)
        #expect(Set(tracker.finished.keys) == ["b"])
    }

    /// Watching it finish: the Claude app in front with that session open counts once the grace has passed.
    @Test func theClaudeSessionOnScreenIsViewedAfterTheGrace() {
        let sessions = [app("a", .claude, desktopID: "local_a"), app("b", .claude, desktopID: "local_b")]
        let signals = SessionViewSignals(claudeFocusedAt: ["local_a": t0 - 60, "local_b": t0 - 600])
        var tracker = finishedTracker("a", "b")
        let claude = FinishedTracker.claudeAppBundleID
        tracker.reviewViewed(sessions: sessions, signals: signals, frontmost: claude, hostBundleID: { _ in nil }, now: t0 + 5)
        #expect(tracker.finished.count == 2)
        tracker.reviewViewed(sessions: sessions, signals: signals, frontmost: "com.apple.Safari", hostBundleID: { _ in nil }, now: t0 + 60)
        #expect(tracker.finished.count == 2)
        tracker.reviewViewed(sessions: sessions, signals: signals, frontmost: claude, hostBundleID: { _ in nil }, now: t0 + 60)
        #expect(Set(tracker.finished.keys) == ["b"])
    }

    @Test func aCodexThreadIsViewedWhenItLeavesTheUnreadList() {
        let sessions = [app("codex:t1", .codex)]
        var tracker = finishedTracker("codex:t1")
        tracker.reviewViewed(sessions: sessions, signals: SessionViewSignals(codexUnread: ["t1"]), frontmost: nil,
                             hostBundleID: { _ in nil }, now: t0 + 2)
        #expect(tracker.finished.count == 1)
        tracker.reviewViewed(sessions: sessions, signals: SessionViewSignals(codexUnread: ["t1"]),
                             frontmost: FinishedTracker.codexAppBundleID, hostBundleID: { _ in nil }, now: t0 + 60)
        #expect(tracker.finished.count == 1)
        tracker.reviewViewed(sessions: sessions, signals: SessionViewSignals(codexUnread: []), frontmost: nil,
                             hostBundleID: { _ in nil }, now: t0 + 90)
        #expect(tracker.finished.isEmpty)
    }

    /// Never unread: it was on screen as it finished, which counts with the Codex app in front after the grace. Not
    /// unread yet a moment after finishing, with another app in front, proves nothing.
    @Test func aCodexThreadNeverMarkedUnreadNeedsTheCodexAppInFront() {
        let sessions = [app("codex:t1", .codex)]
        var tracker = finishedTracker("codex:t1")
        let none = SessionViewSignals(codexUnread: [])
        tracker.reviewViewed(sessions: sessions, signals: none, frontmost: "com.apple.Safari", hostBundleID: { _ in nil }, now: t0 + 60)
        #expect(tracker.finished.count == 1)
        tracker.reviewViewed(sessions: sessions, signals: none, frontmost: FinishedTracker.codexAppBundleID,
                             hostBundleID: { _ in nil }, now: t0 + 5)
        #expect(tracker.finished.count == 1)
        tracker.reviewViewed(sessions: sessions, signals: none, frontmost: FinishedTracker.codexAppBundleID,
                             hostBundleID: { _ in nil }, now: t0 + 60)
        #expect(tracker.finished.isEmpty)
    }

    /// Terminal and Copilot sessions have no per-session signal: their app in front, after the grace.
    @Test func otherSessionsAreViewedWhenTheirAppIsInFront() {
        let terminal = app("t", .claude, origin: .terminal)
        let copilot = app("copilot:c", .copilot)
        var tracker = finishedTracker("t", "copilot:c")
        let hosts = ["t": "com.apple.Terminal", "copilot:c": "com.github.githubapp"]
        tracker.reviewViewed(sessions: [terminal, copilot], signals: nil, frontmost: "com.apple.Terminal",
                             hostBundleID: { hosts[$0.id] }, now: t0 + 5)
        #expect(tracker.finished.count == 2)
        tracker.reviewViewed(sessions: [terminal, copilot], signals: nil, frontmost: "com.apple.Terminal",
                             hostBundleID: { hosts[$0.id] }, now: t0 + 60)
        #expect(Set(tracker.finished.keys) == ["copilot:c"])
    }
}

@Suite struct SessionViewReaderTests {
    @Test func lastFocusedAtComesFromTheFileHead() {
        let head = Data(#"{"sessionId":"local_x","title":"t","lastFocusedAt":1792283809694,"cwd":"/x"}"#.utf8)
        #expect(SessionViewReader.lastFocusedAt(head: head) == Date(timeIntervalSince1970: 1_792_283_809.694))
        #expect(SessionViewReader.lastFocusedAt(head: Data(#"{"sessionId":"local_x"}"#.utf8)) == nil)
        #expect(SessionViewReader.lastFocusedAt(head: Data(#"{"lastFocusedAt":12}"#.utf8)) == nil)
    }

    @Test func codexUnreadJoinsEveryIdentityAndHost() {
        let state = Data(#"""
        {"electron-thread-read-state-v1":{"version":1,"unreadByIdentity":{
          "i1":{"local:h1":["AAA-1","bbb-2"]},"i2":{"local:h2":["ccc-3"],"remote:h3":[]}}}}
        """#.utf8)
        #expect(SessionViewReader.codexUnread(in: state) == ["aaa-1", "bbb-2", "ccc-3"])
        #expect(SessionViewReader.codexUnread(in: Data(#"{"other":1}"#.utf8)) == nil)
    }

    @Test func readsTheListedClaudeSessionsAndCodexUnread() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Claude", isDirectory: true)
        let folder = support.appendingPathComponent("claude-code-sessions/acct/org", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"sessionId":"local_a","lastFocusedAt":1792000000000}"#.utf8)
            .write(to: folder.appendingPathComponent("local_a.json"))
        let codex = root.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try Data(#"{"electron-thread-read-state-v1":{"unreadByIdentity":{"i":{"local:h":["t1"]}}}}"#.utf8)
            .write(to: codex.appendingPathComponent(".codex-global-state.json"))
        let reader = SessionViewReader(
            paths: ClaudePaths(claudeDirectory: root.appendingPathComponent(".claude"), desktopSupportDirectory: support),
            codex: CodexPaths(codexDirectory: codex)
        )
        let signals = reader.read(claudeDesktopIDs: ["local_a", "local_missing"], codex: true)
        #expect(signals.claudeFocusedAt == ["local_a": Date(timeIntervalSince1970: 1_792_000_000)])
        #expect(signals.codexUnread == ["t1"])
        #expect(signals.claudeMostRecentlyFocused == "local_a")
    }
}
