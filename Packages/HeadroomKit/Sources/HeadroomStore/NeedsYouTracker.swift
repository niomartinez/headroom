import Foundation
import HeadroomModel

/// Which sessions that need you the user has seen or dismissed (1.1 §14.4). After the 4 s "harbor needs you"
/// moment the pill keeps "(!) harbor" until the panel is opened (seen), the session stops waiting, or the user
/// dismisses it in the panel. Pure state: the app feeds it every applied snapshot (never sample data), records the
/// panel opening and Dismiss clicks, and persists it (Codable: only the marks), so a relaunch doesn't nag about
/// what was already seen while a new wait alerts again.
///
/// An *episode* is one uninterrupted stretch of `waitingForInput`. It starts at the earlier of "Headroom first saw
/// it waiting" and the session's own `activitySince`, so after a relaunch (first sighting = launch) it still dates
/// from when the session began waiting, and a later `activitySince` inside the same stretch doesn't start a new
/// one. A mark belongs to the episode it was made in: it covers the session's current episode when it was made at
/// or after that episode's start, so a wait that starts after it is new.
public struct NeedsYouTracker: Sendable, Equatable, Codable {
    /// Marks older than this are dropped even while their session is still listed (sessions that ended are never
    /// listed again, so theirs would otherwise stay forever).
    public static let retention: TimeInterval = 7 * 86_400

    /// The user saw or dismissed one waiting episode of one session.
    public struct Mark: Sendable, Hashable, Codable {
        public var sessionID: String
        /// When the episode began, as known when the mark was made.
        public var episodeStart: Date
        /// When the user saw or dismissed it.
        public var at: Date

        public init(sessionID: String, episodeStart: Date, at: Date) {
            self.sessionID = sessionID
            self.episodeStart = episodeStart
            self.at = at
        }
    }

    /// Episodes the user saw (the panel was open while they waited), at most one per session. Persisted.
    public private(set) var seen: [Mark]
    /// Episodes the user dismissed, at most one per session. Persisted.
    public private(set) var dismissed: [Mark]
    /// Session id → the start of its current waiting episode. Rebuilt from snapshots; never persisted, since a
    /// session may have stopped and started waiting again while Headroom wasn't running.
    public private(set) var episodes: [String: Date] = [:]

    private enum CodingKeys: String, CodingKey {
        case seen, dismissed
    }

    public init(seen: [Mark] = [], dismissed: [Mark] = []) {
        self.seen = seen
        self.dismissed = dismissed
    }

    /// Call with every applied snapshot's sessions (not sample data). Starts episodes for sessions that began
    /// waiting and ends them for sessions that stopped. Forgets the marks of sessions that are listed but no longer
    /// waiting, marks of an earlier episode, and marks past `retention`. Sessions missing from the list keep their
    /// marks (an unreadable registry must not bring dismissed rows back), until `retention` passes.
    public mutating func update(sessions: [SessionInfo], now: Date) {
        var next: [String: Date] = [:]
        for session in sessions where session.activity == .waitingForInput {
            let firstSeen = episodes[session.id] ?? now
            next[session.id] = min(firstSeen, session.activitySince ?? firstSeen)
        }
        episodes = next
        let listedNotWaiting = Set(sessions.map(\.id)).subtracting(next.keys)
        let cutoff = now.addingTimeInterval(-Self.retention)
        let keeps = { (mark: Mark) -> Bool in
            guard mark.at > cutoff, !listedNotWaiting.contains(mark.sessionID) else { return false }
            // A mark from before the current episode began belongs to an earlier one.
            return next[mark.sessionID].map { mark.at >= $0 } ?? true
        }
        seen = seen.filter(keeps)
        dismissed = dismissed.filter(keeps)
    }

    /// Waiting, and dismissed during this episode.
    public func isDismissed(_ id: String) -> Bool {
        covers(dismissed, id)
    }

    /// Waiting, neither seen nor dismissed during this episode.
    public func isUnseen(_ id: String) -> Bool {
        episodes[id] != nil && !covers(seen, id) && !isDismissed(id)
    }

    /// The unseen sessions in `sessions` order (the snapshot's display order): the pill's rest state.
    public func unseen(in sessions: [SessionInfo]) -> [SessionInfo] {
        sessions.filter { isUnseen($0.id) }
    }

    /// The waiting sessions the user dismissed.
    public var dismissedIDs: Set<String> {
        Set(episodes.keys.filter(isDismissed))
    }

    /// The panel opened: everything waiting now counts as seen.
    public mutating func markAllSeen(now: Date) {
        for (id, start) in episodes where isUnseen(id) {
            Self.replace(&seen, with: Mark(sessionID: id, episodeStart: start, at: now))
        }
    }

    /// "Dismiss" on a Needs you row: this waiting episode stops counting (pill text, amber dot, count, widgets).
    /// Nothing happens for a session that isn't waiting.
    public mutating func dismiss(_ id: String, now: Date) {
        guard let start = episodes[id] else { return }
        Self.replace(&dismissed, with: Mark(sessionID: id, episodeStart: start, at: now))
    }

    /// "Show in Needs you again".
    public mutating func undoDismiss(_ id: String) {
        dismissed.removeAll { $0.sessionID == id }
    }

    /// What the app shows and publishes: `snapshot` with the dismissed waits read as idle, and who is unseen.
    /// Call after `update(sessions:now:)` with the same snapshot. Moments are still detected on the raw snapshot.
    public func presentation(of snapshot: HeadroomSnapshot) -> NeedsYouPresentation {
        NeedsYouPresentation(snapshot: snapshot, dismissedIDs: dismissedIDs, unseen: unseen(in: snapshot.sessions))
    }

    private func covers(_ marks: [Mark], _ id: String) -> Bool {
        guard let start = episodes[id] else { return false }
        return marks.contains { $0.sessionID == id && $0.at >= start }
    }

    private static func replace(_ marks: inout [Mark], with mark: Mark) {
        marks.removeAll { $0.sessionID == mark.sessionID }
        marks.append(mark)
    }
}

/// A snapshot as the pill, panel, VoiceOver summary and widgets show it after the user's "needs you" marks
/// (1.1 §14.4). Pure.
public struct NeedsYouPresentation: Sendable, Equatable {
    /// The snapshot with dismissed waits read as idle, in display order again: they leave the amber dot, the count,
    /// `waitingCount` (AccessibilitySummary, `WidgetSignature`) and the widgets' Needs you.
    public var snapshot: HeadroomSnapshot
    /// Dismissed sessions that still wait: the panel lists them last in Needs you, muted.
    public var dismissedIDs: Set<String>
    /// Waiting sessions not yet seen, in display order: the pill's rest state ("(!) harbor", "(!) 2 need you") and
    /// the panel's wash.
    public var unseen: [SessionInfo]

    public init(snapshot: HeadroomSnapshot, dismissedIDs: Set<String>, unseen: [SessionInfo]) {
        self.snapshot = snapshot.applyingDismissals(dismissedIDs)
        self.dismissedIDs = dismissedIDs
        self.unseen = unseen
    }

    public var unseenIDs: Set<String> { Set(unseen.map(\.id)) }
    /// The unseen sessions' names, for the pill (`NeedsYouAttention`).
    public var unseenNames: [String] { unseen.map(\.name) }
}
