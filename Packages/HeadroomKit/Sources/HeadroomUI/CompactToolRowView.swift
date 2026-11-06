import HeadroomModel
import SwiftUI

/// A tracked tool other than the header's, in one compact row (1.1 §6.3). The grid, in the panel's 328 pt content
/// width: gauge 24 | 10 | name 58 | label 60 (a 10 pt ring key and 4 pt, then the window) | percent 34
/// (right-aligned) | 8 | detail (the rest, about 134, cut at the end). Lines are 16 pt, a row at least 32 pt. Only
/// tools with two windows get ring keys (1.1 §14.2); the others keep the same columns, so the percentages line up.
struct CompactToolRowView: View {
    static let gaugeGap: CGFloat = 10
    static let nameWidth: CGFloat = 58
    /// The ring key and the space after it, at the start of the label column.
    static let glyphSlot: CGFloat = RingKeyGlyph.compactSize + 4
    static let labelWidth: CGFloat = 60
    static let percentWidth: CGFloat = 34
    static let detailGap: CGFloat = 8
    static let lineHeight: CGFloat = 16
    static let rowHeight: CGFloat = 32

    let row: PanelModel.ToolRow
    let actions: PanelActions

    var body: some View {
        HStack(alignment: .center, spacing: Self.gaugeGap) {
            RingGauge(gauge: row.gauge, style: .compact)
                .overlay {
                    GaugeToolIcon(tool: row.tool, gauge: row.gauge, style: .compact, background: HeadroomTheme.panelBackground)
                }
            VStack(alignment: .leading, spacing: 0) {
                if let status = row.status {
                    statusLine(status)
                } else {
                    ForEach(Array(row.lines.enumerated()), id: \.offset) { index, line in
                        limitLine(line, showsName: index == 0)
                    }
                    ForEach(row.notes, id: \.self) { note in
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundStyle(HeadroomTheme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            // Under the label's text ("Monthly"), past the ring key's slot.
                            .padding(.leading, Self.nameWidth + Self.glyphSlot)
                            .frame(maxWidth: .infinity, minHeight: Self.lineHeight, maxHeight: Self.lineHeight, alignment: .leading)
                    }
                }
            }
        }
        .frame(minHeight: Self.rowHeight)
        .help(row.helpText ?? "")
        .accessibilityElement(children: row.status?.action == nil ? .combine : .contain)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityValue(row.accessibilityValue)
    }

    private func name(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(HeadroomTheme.primaryText)
            .lineLimit(1)
            .frame(width: Self.nameWidth, alignment: .leading)
    }

    private func limitLine(_ line: PanelModel.ToolRow.Line, showsName: Bool) -> some View {
        HStack(spacing: 0) {
            name(showsName ? row.name : "")
            HStack(spacing: 0) {
                if let ring = line.ring {
                    RingKeyGlyph(
                        ring: ring,
                        color: line.percent.isEmpty || line.percent == "–" ? HeadroomTheme.secondaryText : HeadroomTheme.color(for: line.severity),
                        size: RingKeyGlyph.compactSize
                    )
                    .frame(width: Self.glyphSlot, alignment: .leading)
                } else {
                    Color.clear.frame(width: Self.glyphSlot, height: 1)
                }
                Text(line.label)
                    .font(.system(size: 11))
                    .foregroundStyle(HeadroomTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: Self.labelWidth, alignment: .leading)
            Text(line.percent)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(line.percent == "–" ? HeadroomTheme.secondaryText : HeadroomTheme.color(for: line.severity))
                .lineLimit(1)
                // "100%" is a little wider than the column: it may reach into the label's spare room, never cut.
                .fixedSize()
                .frame(width: Self.percentWidth, alignment: .trailing)
            Text(line.detail)
                .font(.system(size: 11))
                .foregroundStyle(HeadroomTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, Self.detailGap)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: Self.lineHeight)
    }

    private func statusLine(_ status: ToolStatusLine) -> some View {
        HStack(spacing: 0) {
            name(row.name)
            Text(status.message)
                .font(.system(size: 11))
                .foregroundStyle(HeadroomTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if let action = status.action, let title = status.actionTitle {
                Button(title) { actions.perform(action) }
                    .buttonStyle(PanelButtonStyle())
            }
        }
    }
}
