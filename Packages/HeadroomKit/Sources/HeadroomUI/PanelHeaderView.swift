import SwiftUI

/// The 72 pt ring gauge next to the Weekly and 5-hour rows (spec §1.2 item 1), or another tool's rows; with two or
/// more tools tracked, the tool's short name above them (1.1 §6.3). Each row starts with its ring key, and hovering
/// a row dims the gauge's other ring (1.1 §14.2).
struct PanelHeaderView: View {
    /// Between a ring key and its row.
    static let glyphSpacing: CGFloat = 6

    let model: PanelModel
    var actions: PanelActions = .none

    @State private var hovered: GaugeRing?
    @Environment(\.previewHoveredLimitRing) private var previewHovered

    var body: some View {
        let header = model.header
        let emphasis = previewHovered ?? hovered
        let hasKeys = header.rows.contains { $0.ring != nil }
        HStack(alignment: .center, spacing: 16) {
            RingGauge(gauge: header.gauge, style: .panel, emphasis: emphasis)
                .overlay {
                    if header.toolName != nil, let tool = header.tool {
                        GaugeToolIcon(tool: tool, gauge: header.gauge, style: .panel, background: HeadroomTheme.panelBackground)
                    }
                }
            VStack(alignment: .leading, spacing: 8) {
                if let toolName = header.toolName {
                    Text(toolName)
                        .font(.system(size: 11))
                        .foregroundStyle(HeadroomTheme.secondaryText)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(Array(header.rows.enumerated()), id: \.offset) { _, row in
                    LimitRowView(row: row, isHighlighted: row.ring != nil && row.ring == emphasis)
                        .onHover { inside in
                            guard let ring = row.ring else { return }
                            if inside {
                                hovered = ring
                            } else if hovered == ring {
                                hovered = nil
                            }
                        }
                }
                ForEach(header.notes, id: \.self) { note in
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(HeadroomTheme.secondaryText)
                        .padding(.leading, hasKeys ? RingKeyGlyph.size + Self.glyphSpacing : 0)
                }
                if let status = header.status {
                    ToolStatusView(status: status, actions: actions)
                }
            }
        }
    }
}

struct LimitRowView: View {
    let row: PanelModel.LimitRow
    /// Hovered: a faint highlight behind the row, the gauge's other ring dimmed.
    var isHighlighted = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PanelHeaderView.glyphSpacing) {
            if let ring = row.ring {
                RingKeyGlyph(ring: ring, color: row.badge.map { HeadroomTheme.color(for: $0.severity) } ?? HeadroomTheme.secondaryText)
                    // Centred on the 13 pt title's lowercase letters.
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4.5 }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HeadroomTheme.primaryText)
                    Spacer(minLength: 8)
                    Text(row.badge?.text ?? "–")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(row.badge.map { HeadroomTheme.color(for: $0.severity) } ?? HeadroomTheme.secondaryText)
                }
                Text(row.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(HeadroomTheme.secondaryText)
                    .lineLimit(1)
                ForEach(row.lines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 11))
                        .foregroundStyle(HeadroomTheme.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHighlighted ? HeadroomTheme.rowHighlight : .clear)
                .padding(.horizontal, -6)
                .padding(.vertical, -3)
        }
        .contentShape(Rectangle())
        // "Weekly limit", "89% used, resets about Sunday 7 PM": words instead of "~" and "–".
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityValue(row.accessibilityValue)
    }
}

/// "Connect GitHub in Settings [Settings…]": a tool with nothing to count (1.1 §4.6), in the header.
struct ToolStatusView: View {
    let status: ToolStatusLine
    let actions: PanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(status.message)
                .font(.system(size: 12))
                .foregroundStyle(HeadroomTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let action = status.action, let title = status.actionTitle {
                Button(title) { actions.perform(action) }
                    .buttonStyle(PanelButtonStyle())
            }
        }
    }
}
