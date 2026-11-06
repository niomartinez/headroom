import Foundation
import HeadroomShare

/// Decides, after each applied poll, whether the app rewrites the widgets' file and whether it asks WidgetKit to
/// reload their timelines (1.1 §5.4). macOS grants a widget about 40–70 reloads a day and app-requested reloads
/// draw on that budget, so the poll's 2-second rhythm must never reach WidgetKit. Pure: dates in, decisions out.
///
/// - Write when what the widgets show changed (`WidgetSignature`), and at least every 15 minutes as a heartbeat
///   ("Headroom isn't running" reads the file's age).
/// - Reload for a change at most every 10 minutes. An urgent change may reload after 2 minutes instead, at most 6
///   times an hour: a limit changing color, "needs you" appearing or clearing, sample mode, an access or tool status
///   change, the first write after launch, or waking from sleep. A change that has to wait is reloaded as soon as
///   its spacing allows, on a later poll, even when nothing changed since.
/// - A failed write is tried again after a minute, not on every 2-second poll, and uses up no reload: the reload
///   comes with the write that works.
///
/// Per poll: `shouldWrite`, then (unless the write failed: `writeFailed`) `shouldReload`.
struct WidgetReloadGate {
    struct Decision: Equatable {
        var write: Bool
        var reload: Bool
    }

    static let heartbeat: TimeInterval = 15 * 60
    static let normalSpacing: TimeInterval = 10 * 60
    static let urgentSpacing: TimeInterval = 2 * 60
    static let urgentPerHour = 6
    /// How long after a failed write the next try waits.
    static let failedWriteRetry: TimeInterval = 60

    /// A change the widgets haven't been reloaded for yet.
    enum Pending: Int, Comparable {
        case normal
        case urgent

        static func < (lhs: Pending, rhs: Pending) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private(set) var lastWriteAt: Date?
    private(set) var lastReloadAt: Date?
    /// Reloads that came sooner than `normalSpacing` because of an urgent change, within the last hour.
    private(set) var urgentReloads: [Date] = []
    private(set) var pending: Pending?
    private(set) var lastFailedWriteAt: Date?
    private var wokeUp = false

    /// The Mac woke from sleep: the next decision writes and reloads as an urgent change.
    mutating func noteWake() {
        wokeUp = true
    }

    /// Whether to write the file this poll. `previous` is the signature last written, nil before the first write
    /// since launch (or after a failed one); `current` is this poll's.
    mutating func shouldWrite(previous: WidgetSignature?, current: WidgetSignature, now: Date) -> Bool {
        let changed = previous != current || wokeUp
        if changed {
            let urgent = wokeUp || Self.isUrgent(from: previous, to: current)
            pending = max(pending ?? .normal, urgent ? .urgent : .normal)
        }
        wokeUp = false
        // The change stays pending while a failed write waits to be tried again.
        if let sinceFailure = elapsed(since: lastFailedWriteAt, now: now), sinceFailure < Self.failedWriteRetry {
            return false
        }
        let write = changed || elapsed(since: lastWriteAt, now: now).map { $0 >= Self.heartbeat } ?? true
        if write { lastWriteAt = now }
        return write
    }

    /// This poll's write failed: nothing is reloaded for it, and the next try waits `failedWriteRetry`.
    mutating func writeFailed(now: Date) {
        lastFailedWriteAt = now
        lastWriteAt = nil
    }

    /// Whether to reload the widgets now, after this poll's write (if any) worked.
    mutating func shouldReload(now: Date) -> Bool {
        guard let pending, let reason = reloadAllowed(for: pending, now: now) else { return false }
        if reason == .urgentException { urgentReloads.append(now) }
        lastReloadAt = now
        self.pending = nil
        return true
    }

    /// `shouldWrite` and `shouldReload` for a poll whose write works.
    mutating func decide(previous: WidgetSignature?, current: WidgetSignature, now: Date) -> Decision {
        let write = shouldWrite(previous: previous, current: current, now: now)
        return Decision(write: write, reload: shouldReload(now: now))
    }

    /// Whether a change from `previous` to `current` may reload sooner than the normal spacing.
    static func isUrgent(from previous: WidgetSignature?, to current: WidgetSignature) -> Bool {
        guard let previous else { return true }
        return previous.severities != current.severities
            || previous.waitingCount != current.waitingCount
            || previous.isSample != current.isSample
            || previous.issues != current.issues
            || previous.tools.map(\.status) != current.tools.map(\.status)
    }

    private enum ReloadReason {
        case normal
        case urgentException
    }

    private mutating func reloadAllowed(for pending: Pending, now: Date) -> ReloadReason? {
        guard let sinceReload = elapsed(since: lastReloadAt, now: now) else { return .normal }
        if sinceReload >= Self.normalSpacing { return .normal }
        guard pending == .urgent, sinceReload >= Self.urgentSpacing else { return nil }
        urgentReloads.removeAll { now.timeIntervalSince($0) >= 3600 || $0 > now }
        return urgentReloads.count < Self.urgentPerHour ? .urgentException : nil
    }

    /// Seconds since `date`; nil when there is none, or when the clock was set back past it (start over).
    private func elapsed(since date: Date?, now: Date) -> TimeInterval? {
        guard let date, now >= date else { return nil }
        return now.timeIntervalSince(date)
    }
}
