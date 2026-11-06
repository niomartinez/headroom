import Foundation

/// When the app's `CopilotService` asks GitHub for usage (§4.7). Pure: the service keeps one, asks it before each
/// fetch, records each outcome and schedules its timer at `nextTimerPoll(now:)`.
///
/// - Every 15 minutes after the last success.
/// - When the panel opens and the last success is more than 5 minutes old; once after wake.
/// - Errors back off 1 → 2 → 4 → … → 60 minutes; a 403/429 also waits for its `Retry-After` / `x-ratelimit-reset`.
/// - At most 18 REST requests an hour, 6 polls' worth: each poll reserves `requestsPerPoll`, the most one poll makes.
///
/// No polling while Copilot isn't tracked or connected, or in sample data mode: the service doesn't ask.
public struct CopilotPollPolicy: Sendable, Equatable {
    /// Why the service wants to poll.
    public enum Trigger: Sendable, Equatable {
        /// The 15-minute timer.
        case timer
        /// The panel opened.
        case panelOpened
        /// The Mac woke from sleep.
        case wake
        /// The panel's Refresh button: fetch now, unless backing off or out of budget.
        case manual
        /// Sign-in just finished: fetch right away, whatever the backoff.
        case signedIn
    }

    public static let interval: TimeInterval = 15 * 60
    /// The panel refreshes a reading older than this.
    public static let panelRefreshAge: TimeInterval = 5 * 60
    public static let firstBackoff: TimeInterval = 60
    public static let maximumBackoff: TimeInterval = 60 * 60
    public static let maximumRequestsPerHour = 18
    /// The most requests one usage poll makes: `ai_credit` + `premium_request` (§4.4) + the organization seat's quota.
    public static let requestsPerPoll = 3

    /// When the last poll succeeded.
    public private(set) var lastSuccess: Date?
    /// Failed polls since the last success.
    public private(set) var consecutiveFailures = 0
    /// No poll before this, after a failure (backoff, or the rate limit's own wait).
    public private(set) var blockedUntil: Date?
    /// When each request of the last hour was made (one entry per request).
    private var requests: [Date] = []

    public init() {}

    /// The backoff after `failures` failed polls in a row: 1, 2, 4, … minutes, at most 60.
    public static func backoff(afterFailures failures: Int) -> TimeInterval {
        guard failures > 0 else { return 0 }
        return min(maximumBackoff, firstBackoff * pow(2, Double(min(failures - 1, 16))))
    }

    /// Whether to poll now for `trigger`.
    public func shouldPoll(_ trigger: Trigger, now: Date) -> Bool {
        guard hasBudget(now: now) else { return false }
        if trigger == .signedIn { return true }
        if let blockedUntil, now < blockedUntil { return false }
        switch trigger {
        case .timer:
            return lastSuccess.map { now >= $0.addingTimeInterval(Self.interval) } ?? true
        case .panelOpened:
            return lastSuccess.map { now.timeIntervalSince($0) > Self.panelRefreshAge } ?? true
        case .wake, .manual, .signedIn:
            return true
        }
    }

    /// When the timer should fire next: 15 minutes after the last success, pushed back by a backoff and by the hourly
    /// request budget. `now` when a poll is due.
    public func nextTimerPoll(now: Date) -> Date {
        var due = lastSuccess?.addingTimeInterval(Self.interval) ?? now
        if let blockedUntil { due = max(due, blockedUntil) }
        return max(due, budgetFreesUp(now: now), now)
    }

    /// Counts requests made outside a usage poll, e.g. `GET /user` after sign-in.
    public mutating func recordRequests(_ count: Int, at now: Date) {
        prune(now: now)
        requests += Array(repeating: now, count: max(0, count))
    }

    /// A usage poll succeeded (`.ok`, `.noIndividualUsage` or `.unrecognized`): the backoff resets.
    public mutating func recordSuccess(at now: Date, requests count: Int = requestsPerPoll) {
        recordRequests(count, at: now)
        lastSuccess = now
        consecutiveFailures = 0
        blockedUntil = nil
    }

    /// A usage poll failed with `error`: back off, and for a 403/429 wait at least as long as GitHub asks.
    public mutating func recordFailure(_ error: any Error, at now: Date, requests count: Int = requestsPerPoll) {
        recordRequests(count, at: now)
        consecutiveFailures += 1
        let wait = max(Self.backoff(afterFailures: consecutiveFailures), Self.retryAfter(error) ?? 0)
        blockedUntil = now.addingTimeInterval(wait)
    }

    /// A new sign-in or a disconnect starts over.
    public mutating func reset() {
        lastSuccess = nil
        consecutiveFailures = 0
        blockedUntil = nil
    }

    /// The rate limit's own wait, from `Retry-After` or `x-ratelimit-reset`.
    static func retryAfter(_ error: any Error) -> TimeInterval? {
        switch error {
        case UsageClientError.rateLimited(let retryAfter): retryAfter
        case TokenRefreshError.rateLimited(let retryAfter): retryAfter
        default: nil
        }
    }

    private func recentRequests(now: Date) -> [Date] {
        requests.filter { now.timeIntervalSince($0) < 3600 }.sorted()
    }

    private func hasBudget(now: Date) -> Bool {
        recentRequests(now: now).count + Self.requestsPerPoll <= Self.maximumRequestsPerHour
    }

    /// When enough of the last hour's requests age out for one more poll.
    private func budgetFreesUp(now: Date) -> Date {
        let recent = recentRequests(now: now)
        let excess = recent.count + Self.requestsPerPoll - Self.maximumRequestsPerHour
        guard excess > 0 else { return now }
        return recent[excess - 1].addingTimeInterval(3600)
    }

    private mutating func prune(now: Date) {
        requests = recentRequests(now: now)
    }
}
