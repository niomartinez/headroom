/// SF Symbols used by the panel. Moment symbols live in `MomentDisplay`.
enum Symbols {
    static let terminal = "terminal"
    static let gear = "gearshape.fill"
    /// The footer's Refresh button, next to the gear.
    static let refresh = "arrow.clockwise"
    static let lock = "lock.fill"
    /// After "Open in Claude" on a hovered session row (1.1 §14.3).
    static let openSession = "arrow.up.forward"
    /// The pill's rest state while a session needs you (1.1 §14.4).
    static let needsYou = "exclamationmark.circle.fill"

    static let all = [terminal, gear, refresh, lock, openSession, needsYou]
}
