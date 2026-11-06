import Foundation
import HeadroomModel

/// Pure analysis of desktop samples (spec §3.2). Every function looks only at the samples of the
/// newest sample's org (§2.1) and accepts samples in any order.
public enum DesktopUsageAnalyzer {
    /// The newest org's newest sample as a `PlanUsage` (source `.desktopApp`), with inferred reset times.
    ///
    /// Resets are inferred as of that sample (capped at `now`), not as of `now`: a reset that happened after
    /// the sample stays visible as a past `resetsAt`, which `PlanUsageResolver.resolve` rolls over (§3.1)
    /// instead of pairing pre-reset usage with the following reset. `nil` when there are no samples or the
    /// newest one carries neither limit.
    public static func currentUsage(samples: [DesktopUsageSample], now: Date) -> PlanUsage? {
        let own = samplesOfNewestOrg(samples)
        guard let newest = own.last else { return nil }
        let asOf = min(now, newest.time)

        func reading(_ kind: LimitKind, resetsAt: () -> Date?) -> LimitReading? {
            newest.value(kind).map {
                LimitReading(
                    kind: kind, usedPercent: $0, resetsAt: resetsAt(), resetIsEstimated: true,
                    observedAt: newest.time, source: .desktopApp
                )
            }
        }
        let usage = PlanUsage(
            fiveHour: reading(.fiveHour) { inferFiveHourReset(samples: own, now: asOf) },
            weekly: reading(.weekly) { inferWeeklyReset(samples: own, now: asOf) },
            extraUsagePercent: newest.extra
        )
        return usage.isEmpty ? nil : usage
    }

    /// The org of the newest sample: the account every function here reads (§2.1). Among samples with the same
    /// time the later one in `samples` counts as newer. Nil without samples.
    public static func newestOrg(of samples: [DesktopUsageSample]) -> String? {
        samples.sortedByTime().last?.org
    }

    /// The newest sample's org's samples, oldest first.
    static func samplesOfNewestOrg(_ samples: [DesktopUsageSample]) -> [DesktopUsageSample] {
        let sorted = samples.sortedByTime()
        guard let org = sorted.last?.org else { return [] }
        return sorted.filter { $0.org == org }
    }

    /// One limit's values over time for the newest org, skipping samples without that value.
    static func series(_ kind: LimitKind, in samples: [DesktopUsageSample]) -> [UsagePoint] {
        samplesOfNewestOrg(samples).compactMap { sample in
            sample.value(kind).map { UsagePoint(time: sample.time, value: $0) }
        }
    }
}

struct UsagePoint: Equatable {
    let time: Date
    let value: Double
}
