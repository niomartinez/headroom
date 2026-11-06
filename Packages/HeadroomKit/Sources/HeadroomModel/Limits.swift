import Foundation

/// The two plan limits Headroom tracks.
public enum LimitKind: String, Sendable, Codable, CaseIterable {
    case fiveHour
    case weekly
}

/// Where a limit reading came from (spec §2.1, §2.4).
public enum ReadingSource: String, Sendable, Codable {
    /// `~/Library/Application Support/Claude/plan-usage-history.json`, written by the Claude desktop app.
    case desktopApp
    /// `~/.claude/headroom/statusline-latest.json`, written by the bridge from a terminal session's status line.
    case terminal
}

/// One observation of one limit.
public struct LimitReading: Sendable, Equatable, Codable {
    public var kind: LimitKind
    /// Percent of the limit used, 0...100 (can exceed 100 if the source says so; the UI clamps).
    public var usedPercent: Double
    /// When the limit resets. `nil` = unknown, or (5-hour) no active window.
    public var resetsAt: Date?
    /// `true` when `resetsAt` was inferred from history rather than reported exactly.
    public var resetIsEstimated: Bool
    /// When the source recorded this value.
    public var observedAt: Date
    public var source: ReadingSource

    public init(
        kind: LimitKind,
        usedPercent: Double,
        resetsAt: Date?,
        resetIsEstimated: Bool,
        observedAt: Date,
        source: ReadingSource
    ) {
        self.kind = kind
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.resetIsEstimated = resetIsEstimated
        self.observedAt = observedAt
        self.source = source
    }

    /// Spec §3.1: stale when older than `staleAfter` (30 min by default).
    public func isStale(now: Date, staleAfter: TimeInterval = PlanUsage.staleAfter) -> Bool {
        now.timeIntervalSince(observedAt) > staleAfter
    }

    /// The reading as of `now` (spec §3.1). After `resetsAt` passes: five-hour → 0 % and no window ("not
    /// started"); weekly → 0 % and the next weekly repeat, keeping its estimated flag. With `resetsAt` unknown, a
    /// reading a whole window old has certainly reset too: → 0 %, reset still unknown.
    public func rolledOver(now: Date) -> LimitReading {
        var rolled = self
        guard let resetsAt else {
            if now.timeIntervalSince(observedAt) >= kind.windowLength { rolled.usedPercent = 0 }
            return rolled
        }
        guard resetsAt <= now else { return self }
        rolled.usedPercent = 0
        switch kind {
        case .fiveHour: rolled.resetsAt = nil
        case .weekly: rolled.resetsAt = Self.firstRepeat(of: resetsAt, every: LimitKind.weekly.windowLength, after: now)
        }
        return rolled
    }

    /// `start + period × k` for the smallest integer `k` that lands strictly after `now`.
    private static func firstRepeat(of start: Date, every period: TimeInterval, after now: Date) -> Date {
        let k = (now.timeIntervalSince(start) / period).rounded(.down) + 1
        return start.addingTimeInterval(k * period)
    }
}

private extension LimitKind {
    /// How long one window of this limit lasts at most: 5 hours or 7 days.
    var windowLength: TimeInterval {
        self == .weekly ? 7 * 24 * 3600 : 5 * 3600
    }
}

/// The account's plan limits as Headroom currently believes them.
public struct PlanUsage: Sendable, Equatable, Codable {
    public static let staleAfter: TimeInterval = 30 * 60

    public var fiveHour: LimitReading?
    public var weekly: LimitReading?
    /// Extra usage percent when the source reports it (desktop `xu`), else nil.
    public var extraUsagePercent: Double?

    public init(fiveHour: LimitReading? = nil, weekly: LimitReading? = nil, extraUsagePercent: Double? = nil) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.extraUsagePercent = extraUsagePercent
    }

    public static let empty = PlanUsage()

    public func reading(_ kind: LimitKind) -> LimitReading? {
        switch kind {
        case .fiveHour: fiveHour
        case .weekly: weekly
        }
    }

    public var isEmpty: Bool { fiveHour == nil && weekly == nil }

    /// The most recent `observedAt` across both limits.
    public var newestObservation: Date? {
        [fiveHour?.observedAt, weekly?.observedAt].compactMap { $0 }.max()
    }

    /// The limit closest to running out, if any.
    public var tightest: LimitReading? {
        [weekly, fiveHour].compactMap { $0 }.max { $0.usedPercent < $1.usedPercent }
    }

    /// Both readings as of `now` (`LimitReading.rolledOver(now:)`); `extraUsagePercent` is kept.
    public func rolledOver(now: Date) -> PlanUsage {
        PlanUsage(
            fiveHour: fiveHour?.rolledOver(now: now),
            weekly: weekly?.rolledOver(now: now),
            extraUsagePercent: extraUsagePercent
        )
    }
}
