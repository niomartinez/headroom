import Foundation
import HeadroomModel

extension DesktopUsageAnalyzer {
    /// When the current five-hour window ends, or `nil` when no window is active or its end is not after
    /// `now` (spec §3.2).
    ///
    /// Walks back from the newest sample while the samples belong to one window; the window started about
    /// half a sampling gap (at most 7.5 min) before the first sample of that run.
    public static func inferFiveHourReset(samples: [DesktopUsageSample], now: Date) -> Date? {
        let points = series(.fiveHour, in: samples)
        guard let newest = points.last, newest.value > 0 else { return nil }

        var first = points.count - 1
        while first > 0, continueSameWindow(points[first - 1], points[first]) {
            first -= 1
        }
        var start = points[first].time
        if first > 0 {
            let gap = start.timeIntervalSince(points[first - 1].time)
            start.addTimeInterval(-min(gap, ResetTiming.desktopSampleInterval) / 2)
        }
        let reset = start.addingTimeInterval(ResetTiming.fiveHours)
        return reset > now ? reset : nil
    }

    /// `later` is in `earlier`'s window when `earlier` had usage, usage did not fall, and < 5 h passed.
    private static func continueSameWindow(_ earlier: UsagePoint, _ later: UsagePoint) -> Bool {
        earlier.value > 0
            && !LimitKind.fiveHour.isResetDrop(from: earlier.value, to: later.value)
            && later.time.timeIntervalSince(earlier.time) < ResetTiming.fiveHours
    }
}
