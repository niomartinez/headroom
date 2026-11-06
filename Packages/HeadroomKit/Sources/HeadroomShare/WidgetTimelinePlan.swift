import Foundation
import HeadroomModel

/// When the widgets' timeline entries fall and when WidgetKit should ask for a new timeline (1.1 §5.5). Pure, so the
/// extension's providers and the tests share it.
///
/// Entries come every 5 minutes for an hour ("Updated 7m ago" keeps counting), plus the moments within 6 hours
/// when what a widget shows changes without new data: a limit resetting (each entry rebuilds its models after
/// `rolledOver(now:)`), a reading turning stale ("as of"), and the file getting old enough to read "Headroom isn't
/// running".
public enum WidgetTimelinePlan {
    /// The regular spacing between entries.
    public static let step: TimeInterval = 5 * 60
    /// How far the regular entries reach.
    public static let horizon: TimeInterval = 60 * 60
    /// How far resets and staleness add entries.
    public static let eventHorizon: TimeInterval = 6 * 3600
    /// Entries closer than this are merged: a minute is the widgets' finest resolution anyway.
    public static let minimumSpacing: TimeInterval = 60
    /// While the file is younger than this, WidgetKit reloads after `freshReload`; after, only after `staleReload`.
    public static let freshFor: TimeInterval = 20 * 60
    public static let freshReload: TimeInterval = 20 * 60
    public static let staleReload: TimeInterval = 60 * 60

    /// The entry dates for `file` as of `now`: `now` first, sorted, at least `minimumSpacing` apart. Event dates
    /// (resets, staleness, "isn't running") win over the regular 5-minute ones they fall next to. Without a file
    /// there is nothing that could change: `[now]`.
    public static func entryDates(for file: WidgetSnapshotFile?, now: Date) -> [Date] {
        guard let file else { return [now] }
        let regular = stride(from: 0, through: horizon, by: step).map { now.addingTimeInterval($0) }
        let events = eventDates(in: file)
            .filter { $0 > now.addingTimeInterval(minimumSpacing / 2) && $0 <= now.addingTimeInterval(eventHorizon) }
            .sorted()

        var kept: [Date] = [now]
        for event in events where event.timeIntervalSince(kept[kept.count - 1]) >= minimumSpacing {
            kept.append(event)
        }
        for date in regular.dropFirst()
        where !kept.contains(where: { abs($0.timeIntervalSince(date)) < minimumSpacing }) {
            kept.append(date)
        }
        return kept.sorted()
    }

    /// When WidgetKit should ask for the next timeline (`.after(date)`): 20 minutes from `now` while the file is
    /// fresh (under 20 minutes old), else an hour. The app also reloads the timelines itself when what the widgets
    /// show changes (`WidgetReloadGate`, §5.4).
    public static func nextReload(for file: WidgetSnapshotFile?, now: Date) -> Date {
        guard let file, now.timeIntervalSince(file.writtenAt) < freshFor else {
            return now.addingTimeInterval(staleReload)
        }
        return now.addingTimeInterval(freshReload)
    }

    /// Every date at which the file's content reads differently without new data.
    static func eventDates(in file: WidgetSnapshotFile) -> [Date] {
        let snapshot = file.snapshot
        var dates = [file.writtenAt.addingTimeInterval(WidgetSnapshotFile.notRunningAfter)]
        for reading in [snapshot.plan.weekly, snapshot.plan.fiveHour].compactMap({ $0 }) {
            dates.append(reading.observedAt.addingTimeInterval(PlanUsage.staleAfter))
            if let resetsAt = reading.resetsAt { dates.append(resetsAt) }
        }
        for usage in [snapshot.codex, snapshot.copilot].compactMap({ $0 }) {
            for limit in usage.limits + usage.otherBuckets.flatMap(\.limits) {
                dates.append(limit.observedAt.addingTimeInterval(usage.staleAfter))
                if let resetsAt = limit.resetsAt { dates.append(resetsAt) }
            }
        }
        return dates
    }
}
