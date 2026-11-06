import Foundation
import HeadroomModel
import HeadroomSamples
import HeadroomShare
import HeadroomWidgetUI
import OSLog
import WidgetKit

struct LimitsEntry: TimelineEntry {
    let date: Date
    /// Nil: no file, or one this version can't read ("Open Headroom").
    let file: WidgetSnapshotFile?
    let choice: WidgetToolChoice
}

struct SessionsEntry: TimelineEntry {
    let date: Date
    let file: WidgetSnapshotFile?
}

/// Where the entries' data comes from: the app's file, or made-up data for the placeholder and the gallery.
enum WidgetData {
    /// The app's file in the App Group container. Nil without a group (Debug, ad-hoc) or when the file is missing or
    /// unreadable: I/O failure on the container means "no data" (§5.3).
    static func current() -> WidgetSnapshotFile? {
        guard let url = WidgetShare.fileURL() else { return nil }
        return WidgetSnapshotFile.read(from: url)
    }

    /// The placeholder and the gallery preview: sample data, marked as such (§5.5, §6.5).
    static func sample(now: Date) -> WidgetSnapshotFile {
        WidgetSnapshotFile.scrubbing(
            SampleData(now: now).showcase(terminalConnected: true), writtenAt: now, isSample: true, pillTool: .claude,
            showsSessionNames: true
        )
    }

    /// Entries at the plan's dates (§5.5), each rebuilding its models at its own date; WidgetKit asks again after
    /// 20 minutes while the file is fresh, else after an hour.
    static func timeline<Entry: TimelineEntry>(now: Date, entry: (Date, WidgetSnapshotFile?) -> Entry) -> Timeline<Entry> {
        let file = current()
        let dates = WidgetTimelinePlan.entryDates(for: file, now: now)
        return Timeline(
            entries: dates.map { entry($0, file) },
            policy: .after(WidgetTimelinePlan.nextReload(for: file, now: now))
        )
    }
}

/// Logs `context.displaySize` once per family, so the render sizes (headroom-render WidgetScenes.swift) can be
/// checked against a real desktop: `log stream --predicate 'subsystem == "com.niomartinez.headroom.widgets"'`.
enum DisplaySizeLog {
    private static let logger = Logger(subsystem: "com.niomartinez.headroom.widgets", category: "layout")
    private static let logged = OSAllocatedUnfairLock(initialState: Set<String>())

    static func note(_ context: TimelineProviderContext) {
        let family = String(describing: context.family)
        guard logged.withLock({ $0.insert(family).inserted }) else { return }
        let size = context.displaySize
        logger.info("\(family, privacy: .public) displaySize \(size.width, privacy: .public)×\(size.height, privacy: .public)")
    }
}

struct LimitsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LimitsEntry {
        let now = Date()
        return LimitsEntry(date: now, file: WidgetData.sample(now: now), choice: .automatic)
    }

    func snapshot(for configuration: SelectToolIntent, in context: Context) async -> LimitsEntry {
        DisplaySizeLog.note(context)
        let now = Date()
        let file = context.isPreview ? WidgetData.sample(now: now) : WidgetData.current()
        return LimitsEntry(date: now, file: file, choice: configuration.tool.choice)
    }

    func timeline(for configuration: SelectToolIntent, in context: Context) async -> Timeline<LimitsEntry> {
        DisplaySizeLog.note(context)
        let choice = configuration.tool.choice
        return WidgetData.timeline(now: Date()) { LimitsEntry(date: $0, file: $1, choice: choice) }
    }
}

struct SessionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> SessionsEntry {
        let now = Date()
        return SessionsEntry(date: now, file: WidgetData.sample(now: now))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (SessionsEntry) -> Void) {
        DisplaySizeLog.note(context)
        let now = Date()
        completion(SessionsEntry(date: now, file: context.isPreview ? WidgetData.sample(now: now) : WidgetData.current()))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<SessionsEntry>) -> Void) {
        DisplaySizeLog.note(context)
        completion(WidgetData.timeline(now: Date()) { SessionsEntry(date: $0, file: $1) })
    }
}
