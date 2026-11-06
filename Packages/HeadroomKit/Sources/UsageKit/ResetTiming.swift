import Foundation
import HeadroomModel

enum ResetTiming {
    static let week: TimeInterval = 7 * 24 * 3600
    static let fiveHours: TimeInterval = 5 * 3600
    /// How often the desktop app writes a sample while it runs (§2.1).
    static let desktopSampleInterval: TimeInterval = 15 * 60
}

extension LimitKind {
    /// How long one window of this limit lasts at most.
    var window: TimeInterval {
        self == .weekly ? ResetTiming.week : ResetTiming.fiveHours
    }

    /// Whether usage falling from `earlier` to `later` means the limit reset in between.
    ///
    /// Weekly keeps the spec's 10 points (§3.2). Five-hour usage never falls inside one window, and the
    /// real history has five-hour resets that fell only 3–5 points, so any whole-point fall counts.
    func isResetDrop(from earlier: Double, to later: Double) -> Bool {
        later <= earlier - (self == .weekly ? 10 : 1)
    }
}

extension Date {
    /// Rounded up to the next full UTC hour; a time already on the hour is kept.
    var roundedUpToFullHour: Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 / 3600).rounded(.up) * 3600)
    }

    /// `self + period × k` for the smallest integer `k` that lands strictly after `now`.
    func firstRepeat(every period: TimeInterval, after now: Date) -> Date {
        let k = (now.timeIntervalSince(self) / period).rounded(.down) + 1
        return addingTimeInterval(k * period)
    }
}
