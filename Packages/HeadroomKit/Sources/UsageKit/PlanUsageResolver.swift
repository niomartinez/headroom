import Foundation
import HeadroomModel

/// Merges the two sources (spec §3.1).
public enum PlanUsageResolver {
    /// `desktopSamples` lets the resolver check that the terminal reading fits the desktop's current account.
    ///
    /// Per limit the newer reading wins (the exact terminal one on a tie). A desktop winner takes the terminal's
    /// exact `resetsAt` when that window was still open at the desktop reading and the terminal reading fits the
    /// newest org's history: the desktop app was on that org from the sample nearest the terminal reading on, no
    /// sample of it earlier in the terminal's window is a reset-sized amount higher, and none after the terminal
    /// reading fell like a reset. Finally a `resetsAt` at or before `now` (or, when unknown, a reading a whole
    /// window old) rolls the reading over (`LimitReading.rolledOver(now:)`).
    /// `extraUsagePercent` always comes from the desktop.
    public static func resolve(
        desktop: PlanUsage?,
        desktopSamples: [DesktopUsageSample],
        terminal: PlanUsage?,
        now: Date
    ) -> PlanUsage {
        func resolved(_ kind: LimitKind) -> LimitReading? {
            winner(desktop: desktop?.reading(kind), terminal: terminal?.reading(kind), samples: desktopSamples)
                .map { $0.rolledOver(now: now) }
        }
        return PlanUsage(
            fiveHour: resolved(.fiveHour),
            weekly: resolved(.weekly),
            extraUsagePercent: desktop?.extraUsagePercent
        )
    }

    private static func winner(
        desktop: LimitReading?, terminal: LimitReading?, samples: [DesktopUsageSample]
    ) -> LimitReading? {
        guard let desktop else { return terminal }
        guard let terminal else { return desktop }
        guard desktop.observedAt > terminal.observedAt else { return terminal }
        guard let exact = terminal.resetsAt, exact > desktop.observedAt,
              desktopAccountSpans(terminal, samples: samples),
              !fallsIntoTerminalReading(terminal, windowEnd: exact, samples: samples),
              !resetSeen(after: terminal, in: samples)
        else { return desktop }
        var borrowed = desktop
        borrowed.resetsAt = exact
        borrowed.resetIsEstimated = false
        return borrowed
    }

    /// Whether the desktop app was already on its current account at the terminal reading: the sample nearest to it
    /// (the newest at or before it, else the oldest) and every later one belong to the newest org. The terminal
    /// reading names no account, so after a switch its windows may be another account's. Without samples nothing
    /// shows the account: false.
    private static func desktopAccountSpans(_ terminal: LimitReading, samples: [DesktopUsageSample]) -> Bool {
        let sorted = samples.sortedByTime()
        guard let org = sorted.last?.org else { return false }
        let nearest = sorted.lastIndex { $0.time <= terminal.observedAt } ?? sorted.startIndex
        return sorted[nearest...].allSatisfy { $0.org == org }
    }

    /// Whether the newest org's last value at or before the terminal reading, taken inside the terminal's window
    /// (the one ending at `windowEnd`), is a reset-sized amount above the terminal's value. Usage never falls inside
    /// a window, so then the terminal is on another account (its CLI login is independent of the desktop app's).
    /// A sample from an earlier window may be higher: the reset in between explains the fall.
    private static func fallsIntoTerminalReading(
        _ terminal: LimitReading, windowEnd: Date, samples: [DesktopUsageSample]
    ) -> Bool {
        guard let earlier = DesktopUsageAnalyzer.series(terminal.kind, in: samples)
            .last(where: { $0.time <= terminal.observedAt })
        else { return false }
        return earlier.time > windowEnd.addingTimeInterval(-terminal.kind.window)
            && terminal.kind.isResetDrop(from: earlier.value, to: terminal.usedPercent)
    }

    /// Whether usage fell like a reset anywhere from the terminal reading through the later desktop samples.
    private static func resetSeen(after terminal: LimitReading, in samples: [DesktopUsageSample]) -> Bool {
        var previous = terminal.usedPercent
        for point in DesktopUsageAnalyzer.series(terminal.kind, in: samples) where point.time > terminal.observedAt {
            if terminal.kind.isResetDrop(from: previous, to: point.value) { return true }
            previous = point.value
        }
        return false
    }
}
