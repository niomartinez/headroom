import HeadroomModel
import SwiftUI

/// The dropdown panel (spec §1.2): always dark, 360 pt wide, corner radius 18. With two or more tools tracked, the
/// header shows the pill's tool and compact rows the others (1.1 §6.3); with only Claude it is 1.0's panel.
public struct PanelView: View {
    static let width: CGFloat = 360
    static let cornerRadius: CGFloat = 18
    static let scrollMargin: CGFloat = 8
    /// Between the header and the compact tool rows, and between those rows.
    static let toolRowsTopPadding: CGFloat = 12
    static let toolRowSpacing: CGFloat = 8

    public let snapshot: HeadroomSnapshot
    public let now: Date
    public let actions: PanelActions
    public let sampleData: PanelSampleData
    /// The "Rings show" choice (nil = Automatic): the header's tool.
    public let tool: ToolID?
    /// The Codex offer above the sessions (the app decides when, 1.1 §6.3).
    public let showsCodexOffer: Bool
    /// Waiting sessions not seen before the panel opened: a faint amber wash (1.1 §14.4).
    public let unseenIDs: Set<String>
    /// Waiting sessions the user dismissed: last in Needs you, muted (1.1 §14.4).
    public let dismissedIDs: Set<String>
    /// Idle sessions not reviewed since they finished: Just finished (1.1.1).
    public let finishedIDs: Set<String>

    @State private var idleExpanded = false

    public init(
        snapshot: HeadroomSnapshot, now: Date, actions: PanelActions, sampleData: PanelSampleData = .hidden,
        tool: ToolID? = nil, showsCodexOffer: Bool = false, unseenIDs: Set<String> = [], dismissedIDs: Set<String> = [],
        finishedIDs: Set<String> = []
    ) {
        self.snapshot = snapshot
        self.now = now
        self.actions = actions
        self.sampleData = sampleData
        self.tool = tool
        self.showsCodexOffer = showsCodexOffer
        self.unseenIDs = unseenIDs
        self.dismissedIDs = dismissedIDs
        self.finishedIDs = finishedIDs
    }

    public var body: some View {
        let model = PanelModel(
            snapshot: snapshot, now: now, idleExpanded: idleExpanded, sampleData: sampleData, tool: tool,
            showsCodexOffer: showsCodexOffer, unseenIDs: unseenIDs, dismissedIDs: dismissedIDs, finishedIDs: finishedIDs,
            openTitles: Self.openTitles(snapshot.sessions, actions: actions)
        )
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)

        let list = SessionListView(model: model, idleExpanded: $idleExpanded, actions: actions)

        VStack(alignment: .leading, spacing: 0) {
            PanelHeaderView(model: model, actions: actions)
            if !model.toolRows.isEmpty {
                VStack(alignment: .leading, spacing: Self.toolRowSpacing) {
                    ForEach(model.toolRows) { CompactToolRowView(row: $0, actions: actions) }
                }
                .padding(.top, Self.toolRowsTopPadding)
            }
            PanelSeparator()
            // Full height when there is room (and in ImageRenderer, which can't draw a ScrollView).
            // When the window is capped to the screen, only the list scrolls, so the header and
            // the gear menu stay reachable.
            ViewThatFits(in: .vertical) {
                list
                // The margin keeps the dot pulse and row highlight, which reach past the list's
                // edges, inside the scroll view's clip.
                ScrollView(.vertical) { list.padding(Self.scrollMargin) }
                    .padding(-Self.scrollMargin)
            }
            PanelSeparator()
            PanelFooterView(model: model, actions: actions)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(width: Self.width, alignment: .leading)
        .background(shape.fill(HeadroomTheme.panelBackground))
        .clipShape(shape)
        .environment(\.colorScheme, .dark)
    }
}

extension PanelView {
    /// Where a click on each session row goes, asked of the app once per draw (1.1 §14.3).
    @MainActor static func openTitles(_ sessions: [SessionInfo], actions: PanelActions) -> [String: String] {
        var titles: [String: String] = [:]
        for session in sessions {
            titles[session.id] = actions.sessionOpenTitle(session.id)
        }
        return titles
    }
}

struct PanelSeparator: View {
    var body: some View {
        Rectangle()
            .fill(HeadroomTheme.separator)
            .frame(height: 1)
            .padding(.vertical, 12)
    }
}

extension EnvironmentValues {
    /// The native panel enables this after keyboard navigation, and clears it on pointer interaction.
    @Entry public var panelKeyboardNavigation = true
}

/// A small pill-shaped button that renders the same everywhere (no AppKit bezel).
struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(HeadroomTheme.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(HeadroomTheme.buttonFill))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
