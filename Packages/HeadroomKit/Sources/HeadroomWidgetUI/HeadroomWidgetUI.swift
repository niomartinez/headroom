import HeadroomModel
import HeadroomShare
import HeadroomUI
import SwiftUI
import WidgetKit

// HeadroomWidgetUI: the Limits and Sessions widget views and their rendering modes (1.1 §5.6, §5.7). Views are
// built from a decoded `WidgetSnapshotFile` at a timeline entry's date; they never read files themselves, and they
// take plain models, so `headroom-render` can draw them outside WidgetKit.

/// The widget kinds this module lays out, with their gallery texts.
public enum HeadroomWidgetUI {
    /// Limits: small and medium. Sessions: medium and large. Any other kind: none.
    public static func supportedFamilies(kind: String) -> [WidgetFamily] {
        switch kind {
        case WidgetShare.limitsKind: [.systemSmall, .systemMedium]
        case WidgetShare.sessionsKind: [.systemMedium, .systemLarge]
        default: []
        }
    }

    public static let limitsName = "Limits"
    /// §14.7's wording: Claude's limits cover chat and Cowork too, not only coding.
    public static let limitsDescription = "Your AI usage limits as rings."
    public static let sessionsName = "Sessions"
    public static let sessionsDescription = "Your agent sessions and how full their context is."
}

/// Which tool a Limits widget shows: the widget's "Tool" option (1.1 §5.6). Automatic means the tool the menu bar
/// rings show (`WidgetSnapshotFile.pillTool`), and on a medium widget one column per tracked tool when there are two
/// or more.
public enum WidgetToolChoice: String, Sendable, CaseIterable, Hashable {
    case automatic
    case claude
    case codex
    case copilot

    /// The fixed tool, or nil for Automatic.
    public var tool: ToolID? {
        switch self {
        case .automatic: nil
        case .claude: .claude
        case .codex: .codex
        case .copilot: .copilot
        }
    }

    /// "Automatic", "Claude", "Codex", "Copilot": the widget's option menu.
    public var title: String {
        tool?.shortName ?? "Automatic"
    }
}

public extension View {
    /// A Headroom widget's container: the panel's dark color in full color, which the system hides when it draws
    /// the widget see-through (accented, vibrant or dimmed), and the dark palette either way (§5.7).
    func headroomWidgetContainer() -> some View {
        containerBackground(for: .widget) { HeadroomTheme.panelBackground }
            .environment(\.colorScheme, .dark)
    }
}
