import Foundation
import HeadroomModel

/// Keeps a working session's `activitySince` at the start of its working run, as far as the builder has seen it
/// (spec §3.4).
///
/// `MomentDetector` announces a finish only for a session that has been working for at least 5 s, judged by its
/// `activitySince`. A desktop session's registry time already says when it started working, but a terminal
/// session's is its newest hook or status line write, which the status line refreshes every few hundred ms while
/// a reply streams in, so on its own it would hide almost every terminal finish. While a session stays working
/// from one build to the next, the earliest `activitySince` seen in that run is kept.
struct WorkingRuns {
    /// The kept `activitySince` of each session that was working in the last build (nil = unknown).
    private var runs: [String: Date?] = [:]

    mutating func applied(to sessions: [SessionInfo]) -> [SessionInfo] {
        var next: [String: Date?] = [:]
        let result = sessions.map { session in
            guard session.activity == .working else { return session }
            var session = session
            if let kept = runs[session.id] {
                session.activitySince = Self.earlier(kept, session.activitySince)
            }
            next[session.id] = session.activitySince
            return session
        }
        runs = next
        return result
    }

    /// Nil (unknown) counts as the earliest, as `sortedForDisplay` and `MomentDetector` treat it.
    private static func earlier(_ a: Date?, _ b: Date?) -> Date? {
        guard let a, let b else { return nil }
        return min(a, b)
    }
}
