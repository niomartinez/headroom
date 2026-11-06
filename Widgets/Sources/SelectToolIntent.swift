import AppIntents
import HeadroomWidgetUI
import WidgetKit

/// The Limits widget's "Tool" option (1.1 §5.6): Automatic follows the menu bar rings.
enum ToolOption: String, AppEnum {
    case automatic
    case claude
    case codex
    case copilot

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tool"
    static let caseDisplayRepresentations: [ToolOption: DisplayRepresentation] = [
        .automatic: "Automatic",
        .claude: "Claude",
        .codex: "Codex",
        .copilot: "Copilot",
    ]

    var choice: WidgetToolChoice {
        WidgetToolChoice(rawValue: rawValue) ?? .automatic
    }
}

struct SelectToolIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Tool"
    static let description = IntentDescription("Choose whose limits the widget shows. Automatic shows the tool the menu bar rings show.")

    @Parameter(title: "Tool", default: .automatic)
    var tool: ToolOption

    init() {}
}
