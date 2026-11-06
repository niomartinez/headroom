import HeadroomModel

/// Moments waiting to be shown in the pill, one at a time (spec §1.1). Pure state: `AppModel`
/// runs the timer and calls `advance()` after `displayDuration`.
struct MomentQueue: Sendable, Equatable {
    static let displayDuration: Duration = .seconds(4)
    /// A burst beyond this (many sessions finishing at once) drops its oldest pending moments,
    /// so the pill never replays events for minutes.
    static let capacity = 5

    private(set) var current: Moment?
    private(set) var pending: [Moment] = []

    /// Queues `moments`, skipping any already showing or queued. Returns the moment to start
    /// showing when nothing was showing.
    mutating func enqueue(_ moments: [Moment]) -> Moment? {
        for moment in moments where moment != current && !pending.contains(moment) {
            pending.append(moment)
        }
        let started = current == nil ? advance() : nil
        if pending.count > Self.capacity {
            pending.removeFirst(pending.count - Self.capacity)
        }
        return started
    }

    /// Ends the current moment and returns the next one, if any.
    mutating func advance() -> Moment? {
        current = pending.isEmpty ? nil : pending.removeFirst()
        return current
    }

    mutating func removeAll() {
        current = nil
        pending.removeAll()
    }

    /// Drops the moments `shouldRemove` matches, queued or showing: "harbor needs you" once the user has seen or
    /// dismissed that wait (1.1 §14.4). Returns `true` when the one showing was dropped; `current` is then the next
    /// one (or nil), which the caller starts showing.
    mutating func removeAll(where shouldRemove: (Moment) -> Bool) -> Bool {
        pending.removeAll(where: shouldRemove)
        guard let current, shouldRemove(current) else { return false }
        _ = advance()
        return true
    }
}

extension Moment {
    /// The session a "needs you" moment is about; nil for every other moment.
    var needsInputSessionID: String? {
        if case let .sessionNeedsInput(sessionID, _) = self { return sessionID }
        return nil
    }
}
