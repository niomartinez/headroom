import HeadroomModel
import SwiftUI

/// Dot, tool symbol, name, project folder, terminal symbol, 44×4 context bar and percentage (spec §1.2
/// item 2). A row the app can open is a plain button, and hovering it shows where the click goes in place of the
/// context bar (1.1 §14.3); a Needs you row shows a Dismiss chip there too (1.1 §14.4).
struct SessionRowView: View {
    static let dotDiameter: CGFloat = 6
    static let spacing: CGFloat = 8
    /// Leading offset of the name, so "Show N more" lines up with it.
    static let textInset = dotDiameter + spacing
    /// A dismissed row's hollow dot.
    static let dismissedDotOpacity = 0.7
    /// An unseen waiting row's wash (1.1 §14.4).
    static let unseenWashOpacity = 0.10

    let row: PanelModel.SessionRow
    var actions: PanelActions = .none
    @State private var hovered = false
    @FocusState private var keyboardFocused: Bool
    @Environment(\.panelKeyboardNavigation) private var keyboardNavigation
    @Environment(\.previewHoveredSessionID) private var previewHoveredID
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var showsHover: Bool { hovered || previewHoveredID == row.id }
    private var isDismissed: Bool { row.attention == .dismissed }
    /// What replaces the context bar while hovered: the Dismiss chip and/or where a click goes.
    private var showsHoverAccessory: Bool { showsHover && (row.canDismiss || row.openTitle != nil) }

    var body: some View {
        clickable
            .overlay(alignment: .trailing) {
                if showsHoverAccessory { hoverAccessory }
            }
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(background))
            .overlay {
                if keyboardFocused && keyboardNavigation {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(HeadroomTheme.secondaryText, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, -6)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .modifier(RowContextMenu(row: row, actions: actions))
            // One element: "Refactor invoice export, ledger, working", value "context 72% full".
            // `.combine` keeps it a static text (a button when openable); the explicit label and value replace the
            // bare parts.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityValue(row.accessibilityValue ?? "")
            .modifier(RowAccessibilityActions(row: row, actions: actions))
            // After `.combine`, so the hover text is attached once, not to each part. On macOS the tooltip is also
            // what VoiceOver reads as the hint, so an openable row leads with where it goes.
            .help(row.tooltip)
    }

    private var background: Color {
        if showsHover { return HeadroomTheme.rowHighlight }
        return row.attention == .unseen ? HeadroomTheme.waiting.opacity(Self.unseenWashOpacity) : .clear
    }

    /// A plain button only when the row opens something, so other rows stay static text.
    @ViewBuilder private var clickable: some View {
        if row.openTitle != nil {
            Button { actions.openSession(row.id) } label: { content }
                .buttonStyle(.plain)
                .focused($keyboardFocused)
                .focusEffectDisabled()
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: Self.spacing) {
            PulsingDot(state: row.dot, diameter: Self.dotDiameter)
                // A dismissed wait keeps its amber, hollow and dimmed: still waiting, no longer asking.
                .environment(\._accessibilityDifferentiateWithoutColor, isDismissed || differentiateWithoutColor)
                .opacity(isDismissed ? Self.dismissedDotOpacity : 1)
            if row.toolTag != nil {
                SessionToolIcon(tool: ToolID(sessionID: row.id))
            }
            // When name and folder don't both fit, they share the row instead of the folder
            // disappearing: it is what tells same-named sessions apart.
            NameAndFolderLayout(spacing: Self.spacing) {
                Text(row.name)
                    .font(.system(size: 13))
                    .foregroundStyle(isDismissed ? HeadroomTheme.secondaryText : HeadroomTheme.primaryText)
                    .lineLimit(1)
                if let projectName = row.projectName {
                    Text(projectName)
                        .font(.system(size: 11))
                        .foregroundStyle(HeadroomTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if row.isTerminal {
                Image(systemName: Symbols.terminal)
                    .font(.system(size: 10))
                    .foregroundStyle(HeadroomTheme.secondaryText)
            }
            Spacer(minLength: 8)
            if let context = row.context {
                ContextBar(fraction: context.fraction, severity: context.severity)
                Text(context.text)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(context.severity == .normal ? HeadroomTheme.secondaryText : HeadroomTheme.color(for: context.severity))
                    .frame(width: 30, alignment: .trailing)
            }
        }
        .frame(height: 24)
        // The whole row is the button, gaps included.
        .contentShape(Rectangle())
    }

    /// "[Dismiss]  Open in Claude ↗" over the row's trailing edge, fading in over whatever it covers.
    private var hoverAccessory: some View {
        HStack(spacing: 8) {
            if row.canDismiss {
                Button("Dismiss") { actions.dismissSession(row.id) }
                    .buttonStyle(PanelButtonStyle())
                    .help(row.attention == .finished
                        ? "Reviewed? Dismiss moves it to Idle."
                        : "Not needed? Dismiss moves it out of the count until this session asks again.")
            }
            if let title = row.openTitle {
                // Only a label: a click on it still reaches the row's button.
                OpenHint(title: title)
                    .allowsHitTesting(false)
            }
        }
        .padding(.leading, OpenHint.fade)
        .background {
            // The hovered row's own color: the panel under the highlight.
            ZStack { HeadroomTheme.panelBackground; HeadroomTheme.rowHighlight }
                .mask(LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12)],
                    startPoint: .leading, endPoint: .trailing
                ))
                .padding(.trailing, -6)
                .allowsHitTesting(false)
        }
        .frame(height: 24)
    }

}

/// A small identity cue shared by the row, the footer legend and per-tool gauges. Different shapes work without color.
struct SessionToolIcon: View {
    static let width: CGFloat = 13
    let tool: ToolID

    static func symbol(for tool: ToolID) -> String {
        switch tool {
        case .claude: "asterisk"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .copilot: "sparkles"
        }
    }

    static func tint(for tool: ToolID) -> Color {
        switch tool {
        case .claude: Color(hex: 0xDFA78F)
        case .codex: Color(hex: 0x9DBEDB)
        case .copilot: Color(hex: 0xC4ACE4)
        }
    }

    var body: some View {
        Image(systemName: Self.symbol(for: tool))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Self.tint(for: tool))
            .frame(width: Self.width)
            .accessibilityHidden(true)
    }
}

/// Right-click on a Needs you row: "Dismiss", or "Show in Needs you again" once dismissed (1.1 §14.4). Other rows
/// get no menu.
private struct RowContextMenu: ViewModifier {
    let row: PanelModel.SessionRow
    let actions: PanelActions

    func body(content: Content) -> some View {
        if row.canDismiss {
            content.contextMenu { Button("Dismiss") { actions.dismissSession(row.id) } }
        } else if row.attention == .dismissed {
            content.contextMenu { Button("Show in Needs you again") { actions.undoDismiss(row.id) } }
        } else {
            content
        }
    }
}

/// "Dismiss" on waiting rows and "Show in Needs you again" on dismissed ones, for VoiceOver (1.1 §14.4).
private struct RowAccessibilityActions: ViewModifier {
    let row: PanelModel.SessionRow
    let actions: PanelActions

    func body(content: Content) -> some View {
        if row.canDismiss {
            content.accessibilityAction(named: "Dismiss") { actions.dismissSession(row.id) }
        } else if row.attention == .dismissed {
            content.accessibilityAction(named: "Show in Needs you again") { actions.undoDismiss(row.id) }
        } else {
            content
        }
    }
}

/// "Open in Claude ↗": where a click on the hovered row goes (1.1 §14.3).
struct OpenHint: View {
    /// The fade over the row's content before the hover accessory.
    static let fade: CGFloat = 16
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Image(systemName: Symbols.openSession)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(HeadroomTheme.primaryText)
        .fixedSize()
        .accessibilityHidden(true)
    }
}

/// The session name followed by its project folder. When both fit they are shown whole. When
/// they don't, a short folder stays whole and the name truncates; a long folder gets the room the
/// name leaves, and at least `minFolderWidth`, truncating in the middle.
struct NameAndFolderLayout: Layout {
    static let minFolderWidth: CGFloat = 60

    var spacing: CGFloat

    /// The widths to offer the name and the folder, given their ideal widths and the width
    /// available to both (nil: unconstrained).
    static func widths(name: CGFloat, folder: CGFloat, spacing: CGFloat, available: CGFloat?) -> (name: CGFloat, folder: CGFloat) {
        guard let available, name + spacing + folder > available else { return (name, folder) }
        let room = max(0, available - spacing)
        let folderWidth = min(folder, room, max(room - name, minFolderWidth))
        return (room - folderWidth, folderWidth)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let placements = placements(width: proposal.width, subviews: subviews)
        let width = placements.last.map { $0.x + $0.size.width } ?? 0
        return CGSize(width: width, height: placements.map(\.size.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, placement) in zip(subviews, placements(width: bounds.width, subviews: subviews)) {
            subview.place(
                at: CGPoint(x: bounds.minX + placement.x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: placement.offer, height: nil)
            )
        }
    }

    /// Left to right: where each subview starts, the width offered to it and the size it takes.
    private func placements(width available: CGFloat?, subviews: Subviews) -> [(x: CGFloat, offer: CGFloat, size: CGSize)] {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified).width }
        var offers = ideals.map { min($0, available ?? $0) }
        if ideals.count == 2 {
            let widths = Self.widths(name: ideals[0], folder: ideals[1], spacing: spacing, available: available)
            offers = [widths.name, widths.folder]
        }
        var x: CGFloat = 0
        return zip(subviews, offers).map { subview, offer in
            let size = subview.sizeThatFits(ProposedViewSize(width: offer, height: nil))
            defer { x += size.width + spacing }
            return (x, offer, size)
        }
    }
}

struct ContextBar: View {
    static let size = CGSize(width: 44, height: 4)

    let fraction: Double
    let severity: Severity

    var body: some View {
        let clamped = min(1, max(0, fraction))
        // A sliver would vanish under the round caps; keep any non-zero fill at least one bar-height wide.
        let fill = clamped > 0 ? max(Self.size.height, Self.size.width * clamped) : 0
        ZStack(alignment: .leading) {
            Capsule().fill(HeadroomTheme.track)
            Capsule().fill(HeadroomTheme.color(for: severity)).frame(width: fill)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }
}
