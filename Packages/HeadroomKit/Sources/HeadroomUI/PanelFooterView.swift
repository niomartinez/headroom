import SwiftUI

/// "Updated 2m ago · from the Claude app", the Refresh button and the gear menu (spec §1.2 item 4). While sample
/// data shows: "Sample data · Turn off".
struct PanelFooterView: View {
    let model: PanelModel
    let actions: PanelActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.panelKeyboardNavigation) private var keyboardNavigation
    /// Each click turns the Refresh arrow once around, so the click shows even when nothing changed.
    @State private var refreshTurns = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.sessionTools.count > 1 {
                HStack(spacing: 14) {
                    ForEach(model.sessionTools, id: \.self) { tool in
                        HStack(spacing: 4) {
                            SessionToolIcon(tool: tool)
                            Text(tool.shortName)
                                .font(.system(size: 10))
                                .foregroundStyle(HeadroomTheme.secondaryText)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Session tools: " + model.sessionTools.map(\.shortName).joined(separator: ", "))
            }
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let turnOff = model.sampleDataTurnOff {
                HStack(spacing: 4) {
                    Text(model.footer)
                        .foregroundStyle(HeadroomTheme.warning)
                    Text("·")
                        .foregroundStyle(HeadroomTheme.secondaryText)
                        .accessibilityHidden(true)
                    Button(turnOff) { actions.hideSampleData() }
                        .buttonStyle(.plain)
                        .foregroundStyle(HeadroomTheme.primaryText)
                        .accessibilityLabel("Turn off sample data")
                }
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            } else {
                Text(model.footer)
                    .font(.system(size: 11))
                    .foregroundStyle(HeadroomTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                actions.refresh()
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.6)) { refreshTurns += 1 }
            } label: {
                // 11 pt: at 12 the arrow stands taller than the footer line and the panel grows.
                Image(systemName: Symbols.refresh)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HeadroomTheme.secondaryText)
                    .rotationEffect(.degrees(Double(refreshTurns) * 360))
            }
            .buttonStyle(.plain)
            .fixedSize()
            // No accent focus ring after a click; Tab and the arrow keys still show it, as the rows do.
            .focusEffectDisabled(!keyboardNavigation)
            .help("Refresh now")
            .accessibilityLabel("Refresh now")
            Menu {
                Button("Settings…") { actions.openSettings() }
                if model.terminalConnected {
                    Button(model.terminalMenuTitle) { actions.disconnectTerminal() }
                } else {
                    Button(model.terminalMenuTitle) { actions.connectTerminal() }
                }
                Divider()
                Button("Quit Headroom") { actions.quit() }
            } label: {
                Image(systemName: Symbols.gear)
                    .font(.system(size: 12))
                    .foregroundStyle(HeadroomTheme.secondaryText)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Headroom menu")
        }
    }
}
