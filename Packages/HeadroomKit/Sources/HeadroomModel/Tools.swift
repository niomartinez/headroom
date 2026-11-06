import Foundation

/// The AI tools Headroom tracks (1.1 spec §2.1). The case order is the fixed display order everywhere.
public enum ToolID: String, Sendable, Codable, CaseIterable, Hashable {
    case claude
    case codex
    case copilot

    /// "Claude", "Codex", "Copilot": tags, compact rows, multi-tool moments.
    public var shortName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .copilot: "Copilot"
        }
    }

    /// "Claude", "OpenAI Codex", "GitHub Copilot": Settings and accessibility.
    public var fullName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "OpenAI Codex"
        case .copilot: "GitHub Copilot"
        }
    }

    /// How old a tool's newest reading may get before it is dimmed: 30 min for Claude and Codex, 45 min for
    /// Copilot, whose billing data lags anyway (§3.4, §4.4).
    public var defaultStaleAfter: TimeInterval {
        switch self {
        case .claude, .codex: 30 * 60
        case .copilot: 45 * 60
        }
    }

    /// The tool a `SessionInfo.id` belongs to, from its prefix (`codex:`, `copilot:`; Claude ids have none), for
    /// moments, which carry only the id: VoiceOver says "Codex session ledger finished" (1.1 §6.2).
    public init(sessionID: String) {
        if sessionID.hasPrefix("codex:") { self = .codex }
        else if sessionID.hasPrefix("copilot:") { self = .copilot }
        else { self = .claude }
    }
}

/// A usage window, named from its length in minutes (§2.1). Codex puts any window in `primary` or `secondary`,
/// so the kind always comes from the length, never from the slot.
///
/// Codable with Swift's synthesized enum format (`{"weekly":{}}`, `{"minutes":{"_0":180}}`, §5.3), so every
/// value, `.minutes(n)` included, round-trips exactly.
public enum WindowKind: Sendable, Codable, Hashable {
    case fiveHour
    case daily
    case weekly
    case monthly
    /// A length (> 0) that matches none of the named windows.
    case minutes(Int)

    /// 240...360 → fiveHour, 1200...1680 → daily, 9000...11000 → weekly, 40000...46000 → monthly, else .minutes(n).
    /// Nil for a length ≤ 0: malformed data, which a reader reports as unrecognized instead of labelling it (1.1 §0.1
    /// invariant 6).
    public init?(windowMinutes: Int) {
        guard windowMinutes > 0 else { return nil }
        switch windowMinutes {
        case 240...360: self = .fiveHour
        case 1200...1680: self = .daily
        case 9000...11000: self = .weekly
        case 40000...46000: self = .monthly
        default: self = .minutes(windowMinutes)
        }
    }

    /// "5-hour", "Daily", "Weekly", "Monthly"; other lengths in whole days, hours or minutes: "2-day", "3-hour",
    /// "90-minute".
    public var title: String {
        switch self {
        case .fiveHour: "5-hour"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .minutes(let n):
            if n > 0, n % 1440 == 0 { "\(n / 1440)-day" }
            else if n > 0, n % 60 == 0 { "\(n / 60)-hour" }
            else { "\(n)-minute" }
        }
    }

    /// 300, 1440, 10080, 43200 or n. Sort limits by this, longest first.
    public var lengthMinutes: Int {
        switch self {
        case .fiveHour: 300
        case .daily: 1440
        case .weekly: 10080
        case .monthly: 43200
        case .minutes(let n): n
        }
    }
}

/// What an absolute Copilot amount counts (§4.4, §4.5).
public enum UsageUnit: String, Sendable, Codable {
    /// Copilot AI credits (current plans).
    case aiCredits
    /// Premium requests (yearly plans on the older billing).
    case premiumRequests
}

/// One limit of one tool: a Codex window or Copilot's monthly allowance (§2.1).
public struct ToolLimit: Sendable, Equatable, Codable {
    public var window: WindowKind
    /// Percent of the limit used, 0...100 (can exceed 100; the UI clamps). Nil when the allowance is unknown
    /// (Copilot "Not sure"): no ring fill and no percent.
    public var usedPercent: Double?
    /// The absolute amount used (Copilot).
    public var used: Double?
    /// The plan's allowance in `unit` (Copilot), from the user's plan choice.
    public var allowance: Double?
    /// Extra usage billed beyond the allowance (Copilot, Σ netQuantity); set only when > 0.
    public var extra: Double?
    /// Set on every Copilot limit and only there: it also selects Copilot's exact month rollover in `rolledOver(now:)`.
    public var unit: UsageUnit?
    /// When the window resets. Nil = unknown, or (5-hour) no active window.
    public var resetsAt: Date?
    /// `true` when `resetsAt` was inferred rather than reported exactly.
    public var resetIsEstimated: Bool
    /// `true` once `rolledOver(now:)` has zeroed a window whose next reset nobody knows: "reset since last reading".
    public var resetSinceReading: Bool
    /// When the source recorded this value.
    public var observedAt: Date

    public init(
        window: WindowKind,
        usedPercent: Double?,
        used: Double? = nil,
        allowance: Double? = nil,
        extra: Double? = nil,
        unit: UsageUnit? = nil,
        resetsAt: Date?,
        resetIsEstimated: Bool = false,
        resetSinceReading: Bool = false,
        observedAt: Date
    ) {
        self.window = window
        self.usedPercent = usedPercent
        self.used = used
        self.allowance = allowance
        self.extra = extra
        self.unit = unit
        self.resetsAt = resetsAt
        self.resetIsEstimated = resetIsEstimated
        self.resetSinceReading = resetSinceReading
        self.observedAt = observedAt
    }

    /// The limit as of `now`, once `resetsAt` has passed (§2.1):
    /// - 5-hour → 0 % (and 0 used), no window ("not started").
    /// - Copilot's monthly limit (monthly with a `unit`) → 0 used, 0 % when a percent is known, no extra billed, and
    ///   the next 1st at 00:00 UTC after `now` (GitHub's exact month boundary).
    /// - any other window, a Codex monthly one included → 0 %, reset unknown, `resetSinceReading`: Codex gives the
    ///   next reset only with a new reading, so none is invented.
    ///
    /// Before `resetsAt`, or with it unknown, the limit is returned unchanged.
    public func rolledOver(now: Date) -> ToolLimit {
        guard let resetsAt, resetsAt <= now else { return self }
        var rolled = self
        rolled.used = used.map { _ in 0 }
        switch window {
        case .fiveHour:
            rolled.usedPercent = usedPercent.map { _ in 0 }
            rolled.resetsAt = nil
        case .monthly where unit != nil:
            rolled.usedPercent = (usedPercent != nil || allowance != nil) ? 0 : nil
            rolled.extra = nil
            rolled.resetsAt = Self.startOfNextUTCMonth(after: now)
        case .daily, .weekly, .monthly, .minutes:
            rolled.usedPercent = usedPercent.map { _ in 0 }
            rolled.resetsAt = nil
            rolled.resetSinceReading = true
        }
        return rolled
    }

    /// The first 1st-of-the-month at 00:00:00 UTC strictly after `date`.
    static func startOfNextUTCMonth(after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let month = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: month)!
        return calendar.date(byAdding: .month, value: 1, to: start)!
    }
}

/// A group of limits that is not the tool's main one: a Codex bucket such as "GPT-5.3-Codex-Spark" (§3.4).
public struct NamedLimits: Sendable, Equatable, Codable {
    /// The source's id (Codex `limit_id`).
    public var id: String
    /// What to show (Codex `limit_name ?? limit_id`).
    public var name: String
    /// Longest window first.
    public var limits: [ToolLimit]

    public init(id: String, name: String, limits: [ToolLimit]) {
        self.id = id
        self.name = name
        self.limits = limits
    }
}

/// Why a tool shows the numbers it shows, or none (§3.4, §4.6).
public enum ToolStatus: String, Sendable, Codable {
    /// A reading is shown.
    case ok
    /// The tool's folder isn't readable (Codex).
    case needsAccess
    /// No rollout has a limits reading, e.g. Codex on an API key: "No Codex limits found".
    case noActivity
    /// The newest reading's format is unknown; no numbers are guessed.
    case unrecognized
    /// Copilot is tracked but GitHub isn't connected.
    case notConnected
    /// The GitHub refresh token was rejected or expired.
    case signInExpired
    /// GitHub reports no usage billed to this account this month (e.g. an organization-paid seat).
    case noIndividualUsage
    /// Network error or a 5xx: the last reading is kept, dimmed.
    case offline
    /// HTTP 403/429: the last reading is kept, dimmed.
    case rateLimited
    /// Copilot is tracked for Copilot CLI sessions only: this build has no GitHub sign-in (empty Client ID, 1.1 §4.8),
    /// so there is no usage and nothing to connect. No limit row, gauge or Connect prompt; the tool still counts as
    /// tracked (`HeadroomSnapshot.trackedTools`: tool tags, "No sessions running", moments that name the tool).
    case sessionsOnly
}

/// One tool's limits as Headroom currently believes them (§2.1).
public struct ToolUsage: Sendable, Equatable, Codable {
    public var tool: ToolID
    /// Longest window first.
    public var limits: [ToolLimit]
    /// The plan's shape: whether it has a 5-hour window at all, so the pill and gauges draw the inner ring's track
    /// (§6.1). False for Codex Pro (weekly only) and Copilot (monthly).
    public var hasFiveHourWindow: Bool
    /// Codex buckets other than "codex", e.g. Spark (§3.4).
    public var otherBuckets: [NamedLimits]
    public var status: ToolStatus
    /// Codex `plan_type` ("Plus", "Pro", "Pro Lite"); Copilot's plan preset ("Pro+").
    public var planName: String?
    /// The Copilot GitHub login.
    public var account: String?
    /// How old the newest observation may get before the tool's rings are dimmed (`ToolID.defaultStaleAfter`).
    public var staleAfter: TimeInterval
    /// Copilot: true when the reading is an organization-paid seat's quota, with GitHub's own allowance, which the
    /// Plan picker doesn't change. Nil otherwise.
    public var organizationSeat: Bool?
    /// Codex: true while no Codex session on this Mac is working (1.1 §14.12). Its limits move only when Codex is
    /// used, so an old reading is still the latest one here: it shows its age but isn't dimmed. Nil otherwise.
    public var quietSinceReading: Bool?

    /// `staleAfter` nil = `tool.defaultStaleAfter`.
    public init(
        tool: ToolID,
        limits: [ToolLimit] = [],
        hasFiveHourWindow: Bool = false,
        otherBuckets: [NamedLimits] = [],
        status: ToolStatus,
        planName: String? = nil,
        account: String? = nil,
        staleAfter: TimeInterval? = nil,
        organizationSeat: Bool? = nil
    ) {
        self.tool = tool
        self.limits = limits
        self.hasFiveHourWindow = hasFiveHourWindow
        self.otherBuckets = otherBuckets
        self.status = status
        self.planName = planName
        self.account = account
        self.staleAfter = staleAfter ?? tool.defaultStaleAfter
        self.organizationSeat = organizationSeat
    }

    /// Claude's `PlanUsage` as a `ToolUsage`, for compact rows, multi-tool pills and widgets: weekly then 5-hour,
    /// `hasFiveHourWindow` true, stale after 30 min, `.ok` with a reading and `.noActivity` without one. Reset
    /// times and their estimated flags carry over; the reading source and extra usage don't. The Claude-only
    /// header keeps using `PlanUsage` directly.
    ///
    /// Roll Claude over with `PlanUsage.rolledOver(now:)` before converting: its weekly reset repeats, which
    /// `ToolLimit.rolledOver(now:)` doesn't assume.
    public init(claude plan: PlanUsage) {
        let limits = [plan.weekly, plan.fiveHour].compactMap { reading in
            reading.map {
                ToolLimit(
                    window: $0.kind == .weekly ? .weekly : .fiveHour,
                    usedPercent: $0.usedPercent,
                    resetsAt: $0.resetsAt,
                    resetIsEstimated: $0.resetIsEstimated,
                    observedAt: $0.observedAt
                )
            }
        }
        self.init(
            tool: .claude,
            limits: limits,
            hasFiveHourWindow: true,
            status: limits.isEmpty ? .noActivity : .ok,
            staleAfter: PlanUsage.staleAfter
        )
    }

    /// Copilot tracked for its CLI sessions only (`.sessionsOnly`): `HeadroomSnapshot.copilot` when Copilot CLI
    /// sessions are tracked and the app has no usage to hand over (1.1 §4.8, §7).
    public static let copilotSessionsOnly = ToolUsage(tool: .copilot, status: .sessionsOnly)

    /// The most recent `observedAt` across `limits`.
    public var newestObservation: Date? {
        limits.map(\.observedAt).max()
    }

    /// The limit with the highest known percent (the longest window on a tie), if any.
    public var tightest: ToolLimit? {
        limits
            .compactMap { limit in limit.usedPercent.map { (limit: limit, percent: $0) } }
            .max { $0.percent < $1.percent }?
            .limit
    }

    /// The limit for `window`, if the tool has one.
    public func limit(_ window: WindowKind) -> ToolLimit? {
        limits.first { $0.window == window }
    }

    /// Stale when the newest observation is more than `staleAfter` old. Without any observation there is
    /// nothing to dim: false.
    public func isStale(now: Date) -> Bool {
        guard let newestObservation else { return false }
        return now.timeIntervalSince(newestObservation) > staleAfter
    }

    /// Stale and dimmed for its age: stale, unless nothing has used the tool since (`quietSinceReading`).
    public func isDimmedForAge(now: Date) -> Bool {
        isStale(now: now) && quietSinceReading != true
    }

    /// Every limit, other buckets' included, rolled over as of `now` (`ToolLimit.rolledOver(now:)`).
    public func rolledOver(now: Date) -> ToolUsage {
        var rolled = self
        rolled.limits = limits.map { $0.rolledOver(now: now) }
        rolled.otherBuckets = otherBuckets.map { bucket in
            var bucket = bucket
            bucket.limits = bucket.limits.map { $0.rolledOver(now: now) }
            return bucket
        }
        return rolled
    }
}
