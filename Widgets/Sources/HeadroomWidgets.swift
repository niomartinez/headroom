import HeadroomShare
import HeadroomWidgetUI
import SwiftUI
import WidgetKit

// The Headroom widget extension (1.1 §5): Limits and Sessions. It reads only the file the app writes into the App
// Group container (WidgetShare.fileURL()); it never reads user folders, holds no credentials and makes no network
// connections. Both kinds are permanent identifiers: renaming one orphans every widget users have placed.

@main
struct HeadroomWidgets: WidgetBundle {
    var body: some Widget {
        LimitsWidget()
        SessionsWidget()
    }
}

/// Limits (small, medium): configurable from day one, since switching a kind's configuration type later risks
/// resetting placed widgets (§5.6).
struct LimitsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetShare.limitsKind, intent: SelectToolIntent.self, provider: LimitsProvider()) { entry in
            LimitsEntryView(entry: entry)
        }
        .configurationDisplayName(HeadroomWidgetUI.limitsName)
        .description(HeadroomWidgetUI.limitsDescription)
        .supportedFamilies(HeadroomWidgetUI.supportedFamilies(kind: WidgetShare.limitsKind))
    }
}

/// Sessions (medium, large).
struct SessionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShare.sessionsKind, provider: SessionsProvider()) { entry in
            SessionsEntryView(entry: entry)
        }
        .configurationDisplayName(HeadroomWidgetUI.sessionsName)
        .description(HeadroomWidgetUI.sessionsDescription)
        .supportedFamilies(HeadroomWidgetUI.supportedFamilies(kind: WidgetShare.sessionsKind))
    }
}

struct LimitsEntryView: View {
    let entry: LimitsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        LimitsWidgetView(
            model: LimitsWidgetModel(file: entry.file, choice: entry.choice, now: entry.date),
            size: family == .systemSmall ? .small : .medium
        )
        .headroomWidgetContainer()
        .widgetURL(WidgetShare.openPanelURL)
    }
}

struct SessionsEntryView: View {
    let entry: SessionsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        SessionsWidgetView(
            model: SessionsWidgetModel(file: entry.file, now: entry.date),
            size: family == .systemLarge ? .large : .medium
        )
        .headroomWidgetContainer()
        .widgetURL(WidgetShare.openPanelURL)
    }
}
