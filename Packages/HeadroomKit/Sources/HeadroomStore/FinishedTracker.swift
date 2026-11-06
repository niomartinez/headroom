import Foundation
import HeadroomModel

/// "Just finished" (1.1.1): a session that finished its work stays in the panel's Just finished section, above Idle,
/// until the user has looked at it: opened it from Headroom, dismissed it (or cleared the section), or it works or
/// asks for input again. Opening the panel doesn't count; the point is to review each result. Pure state: the app
/// feeds it every applied real snapshot (never sample data) with that snapshot's moments, and persists `finished`
/// so a relaunch keeps what wasn't reviewed yet.
///
/// A finish is a `sessionFinished` moment (`MomentDetector`: working at least 5 s, now idle), so it needs two
/// snapshots Headroom saw: a session that finished while Headroom wasn't running is plain idle. Looking at it in its
/// own app counts too (1.1.2, `reviewViewed`), as answering a wait there clears Needs you.
public struct FinishedTracker: Sendable, Equatable {
    /// Marks older than this are dropped even while their session is still listed and idle.
    public static let retention: TimeInterval = 7 * 86_400
    /// How long after a finish "its app is in front" starts to count as having seen it: the app may still be
    /// writing that the session is unread, and a glance at the moment it finishes isn't a look.
    public static let viewGrace: TimeInterval = 15
    public static let claudeAppBundleID = "com.anthropic.claudefordesktop"
    public static let codexAppBundleID = "com.openai.codex"

    /// Session id → when Headroom saw it finish. Persisted.
    public private(set) var finished: [String: Date]
    /// Finished Codex app threads the Codex app has listed as unread since; not persisted.
    private var codexSeenUnread: Set<String> = []

    public init(finished: [String: Date] = [:]) {
        self.finished = finished
    }

    /// Call with every applied snapshot's sessions and its moments (not sample data). Marks the sessions that just
    /// finished; forgets those listed but no longer idle, and marks past `retention`. Sessions missing from the list
    /// keep their marks until `retention` (an unreadable registry must not lose them); an ended session is never
    /// listed again, so its mark just ages out.
    public mutating func update(sessions: [SessionInfo], moments: [Moment], now: Date) {
        for moment in moments {
            if case .sessionFinished(let id, _) = moment {
                finished[id] = now
            }
        }
        let notIdle = Set(sessions.filter { $0.activity != .idle }.map(\.id))
        let cutoff = now.addingTimeInterval(-Self.retention)
        finished = finished.filter { id, at in at > cutoff && !notIdle.contains(id) }
        codexSeenUnread.formIntersection(finished.keys)
    }

    /// Sessions the user looked at in their own app move to Idle (1.1.2, spec 1.1 §14.15). Returns `true` when that
    /// changed anything.
    ///
    /// - A Claude app session: opened in the Claude app after it finished (`lastFocusedAt`), or still the one on
    ///   screen (the most recently opened, with the Claude app in front) once `viewGrace` has passed.
    /// - A Codex app thread: the Codex app listed it as unread and no longer does, or never did and the Codex app is
    ///   in front once `viewGrace` has passed (it was on screen as it finished).
    /// - Anything else (terminal sessions, Copilot, or when those signals can't be read): the app it runs in
    ///   (`hostBundleID`, asked only then) is in front once `viewGrace` has passed.
    ///
    /// `frontmost` is the frontmost app's bundle id; `signals` nil when they weren't read this time.
    @discardableResult
    public mutating func reviewViewed(
        sessions: [SessionInfo], signals: SessionViewSignals?, frontmost: String?,
        hostBundleID: (SessionInfo) -> String?, now: Date
    ) -> Bool {
        var viewed = Set<String>()
        for session in sessions where session.activity == .idle {
            guard let at = finished[session.id] else { continue }
            let settled = now.timeIntervalSince(at) >= Self.viewGrace
            if session.tool == .claude, session.origin == .desktop, let desktopID = session.desktopSessionID,
               let focused = signals?.claudeFocusedAt[desktopID] {
                let onScreen = frontmost == Self.claudeAppBundleID && signals?.claudeMostRecentlyFocused == desktopID
                if focused > at || (onScreen && settled) { viewed.insert(session.id) }
            } else if session.tool == .codex, session.origin == .desktop, let unread = signals?.codexUnread {
                let thread = String(session.id.dropFirst(session.id.hasPrefix("codex:") ? 6 : 0)).lowercased()
                if unread.contains(thread) {
                    codexSeenUnread.insert(session.id)
                } else if codexSeenUnread.contains(session.id) || (frontmost == Self.codexAppBundleID && settled) {
                    viewed.insert(session.id)
                }
            } else if settled, let frontmost, hostBundleID(session) == frontmost {
                viewed.insert(session.id)
            }
        }
        guard !viewed.isEmpty else { return false }
        for id in viewed {
            finished.removeValue(forKey: id)
            codexSeenUnread.remove(id)
        }
        return true
    }

    /// The listed sessions still to review: idle and marked.
    public func ids(in sessions: [SessionInfo]) -> Set<String> {
        Set(sessions.filter { $0.activity == .idle && finished[$0.id] != nil }.map(\.id))
    }

    /// Opened from Headroom, or dismissed: the session moves to Idle. Returns `true` when that changed anything.
    @discardableResult
    public mutating func review(_ id: String) -> Bool {
        finished.removeValue(forKey: id) != nil
    }

    /// "Clear" on the section: every finished session moves to Idle. Returns `true` when that changed anything.
    @discardableResult
    public mutating func reviewAll() -> Bool {
        guard !finished.isEmpty else { return false }
        finished = [:]
        return true
    }
}
