import Foundation
import HeadroomModel

extension DesktopUsageAnalyzer {
    /// The next weekly reset strictly after `now`, or `nil` when the history shows no reset (spec §3.2) or every
    /// schedule it suggests has since missed a reset.
    ///
    /// Each weekly drop of ≥ 10 points is a reset event, estimated at the earlier sample rounded up to the next
    /// full hour and clamped to the later sample. The weekly schedule does not move when a one-off reset happens
    /// mid-week (the real history has one; the terminal kept reporting the old schedule), so rather than trusting
    /// the newest event, the estimate is used whose weekly repeats fall inside the most events' sample
    /// intervals; ties go to the newest event, which reduces to the spec's newest-event rule. A schedule that
    /// missed a reset after its newest supporting event is out, so a schedule that really moved is followed from
    /// the first old repeat that passes without a reset instead of after it has been outvoted.
    public static func inferWeeklyReset(samples: [DesktopUsageSample], now: Date) -> Date? {
        let points = series(.weekly, in: samples)
        let events = weeklyResetEvents(in: points).suffix(maxWeeklyEvents)
        return scheduleAnchor(for: Array(events), flatPairs: flatWeeklyPairs(in: points))?
            .firstRepeat(every: ResetTiming.week, after: now)
    }

    /// A year of weekly resets. The vote is quadratic in the number of events, so this also bounds the work
    /// on a hostile history full of drops.
    static let maxWeeklyEvents = 52

    static func weeklyResetEvents(in points: [UsagePoint]) -> [WeeklyResetEvent] {
        zip(points, points.dropFirst()).compactMap { earlier, later in
            LimitKind.weekly.isResetDrop(from: earlier.value, to: later.value)
                ? WeeklyResetEvent(earliest: earlier.time, latest: later.time)
                : nil
        }
    }

    /// Consecutive weekly samples that rule out a reset between them (see `FlatWeeklyPair`), oldest first.
    static func flatWeeklyPairs(in points: [UsagePoint]) -> [FlatWeeklyPair] {
        zip(points, points.dropFirst()).compactMap { earlier, later in
            let pair = FlatWeeklyPair(earlier: earlier, later: later)
            return pair.rulesOutReset ? pair : nil
        }
    }

    /// `events` oldest first.
    static func scheduleAnchor(for events: [WeeklyResetEvent], flatPairs: [FlatWeeklyPair]) -> Date? {
        var best: (support: Int, anchor: Date)?
        for candidate in events {
            let anchor = candidate.estimate
            let supporting = events.filter { $0.admitsSchedule(through: anchor) }
            // A candidate always supports itself, so `supporting` is never empty.
            guard let newestSupport = supporting.last else { continue }
            let missedReset = flatPairs.contains {
                $0.earlier.time >= newestSupport.latest && $0.missesRepeat(of: anchor, near: events)
            }
            if !missedReset, supporting.count >= best?.support ?? 0 {
                best = (supporting.count, anchor)
            }
        }
        return best?.anchor
    }
}

/// A weekly reset that happened between two consecutive samples: somewhere in `earliest...latest`.
struct WeeklyResetEvent: Equatable {
    let earliest: Date
    let latest: Date

    /// Spec §3.2: the earlier sample rounded up to the next full hour, clamped to the later sample.
    var estimate: Date {
        min(earliest.roundedUpToFullHour, latest)
    }

    /// Whether a weekly schedule through `time` has a reset inside this event's interval.
    func admitsSchedule(through time: Date) -> Bool {
        let weeks = (earliest.timeIntervalSince(time) / ResetTiming.week).rounded(.up)
        return time.addingTimeInterval(weeks * ResetTiming.week) <= latest
    }
}

/// Two consecutive weekly samples between which no reset happened.
struct FlatWeeklyPair: Equatable {
    let earlier: UsagePoint
    let later: UsagePoint

    /// At most 30 min apart, at ≥ 30 %, and no reset drop: to hide a reset in between, more than 20 points
    /// would have to be used again within those 30 min (the real history never used more than 9).
    var rulesOutReset: Bool {
        later.time.timeIntervalSince(earlier.time) <= 2 * ResetTiming.desktopSampleInterval
            && earlier.value >= 30
            && !LimitKind.weekly.isResetDrop(from: earlier.value, to: later.value)
    }

    /// Whether the schedule through `anchor` has a reset between the two samples that no event within an hour of
    /// it explains. A nearby event means the reset came, only not exactly at the estimate (clock skew, a late
    /// sample, or an estimate rounded to the hour).
    func missesRepeat(of anchor: Date, near events: [WeeklyResetEvent]) -> Bool {
        let reset = anchor.firstRepeat(every: ResetTiming.week, after: earlier.time)
        guard reset <= later.time else { return false }
        let slack: TimeInterval = 3600
        return !events.contains {
            $0.earliest <= reset.addingTimeInterval(slack) && $0.latest >= reset.addingTimeInterval(-slack)
        }
    }
}
