import HeadroomModel
import HeadroomUI
import SwiftUI
import WidgetKit

/// The Limits widget (1.1 §5.6): small, or medium with one tool's header or one column per tracked tool. The
/// extension wraps it in `headroomWidgetContainer()` and the widget URL; renders draw it on their own backdrop.
public struct LimitsWidgetView: View {
    public enum Size: Sendable {
        case small
        case medium
    }

    public var model: LimitsWidgetModel
    public var size: Size

    public init(model: LimitsWidgetModel, size: Size) {
        self.model = model
        self.size = size
    }

    public var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium where !model.columns.isEmpty: columns
            case .medium: single
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
    }

    // MARK: Small

    /// The name with the dot and count, a 64 pt gauge with the outer and inner windows' values, and a bottom line
    /// with the reset, the age of a stale reading, or the footer when it says something else.
    private var small: some View {
        let tool = model.tool
        return VStack(alignment: .leading, spacing: 0) {
            header(tool.name)
            Spacer(minLength: 6)
            HStack(alignment: .center, spacing: 8) {
                WidgetGauge(gauge: tool.gauge, drawsInnerTrack: tool.drawsInnerTrack, size: 64)
                VStack(alignment: .leading, spacing: 1) {
                    if let status = tool.status {
                        Text(status)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(HeadroomTheme.primaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let outer = tool.outerRow {
                        LimitValue(row: outer, size: 20)
                        keyedLabel(outer.amountLabel ?? outer.title, row: outer)
                        if let inner = tool.innerRow {
                            LimitValue(row: inner, size: 15)
                                .padding(.top, 3)
                            keyedLabel(inner.title, row: inner)
                        }
                    }
                }
            }
            Spacer(minLength: 6)
            bottomLine
        }
    }

    @ViewBuilder
    private var bottomLine: some View {
        if model.footer.tone != .plain || model.tool.outerRow == nil {
            FooterText(footer: model.footer)
        } else if let outer = model.tool.outerRow {
            Text(outer.shortDetail)
                .font(.system(size: 11))
                .foregroundStyle(HeadroomTheme.secondaryText)
                .lineLimit(1)
        }
    }

    // MARK: Medium, one tool

    /// The panel header for one tool: the gauge, then the name over its limit rows and their detail lines.
    private var single: some View {
        let tool = model.tool
        return HStack(alignment: .center, spacing: 16) {
            WidgetGauge(gauge: tool.gauge, drawsInnerTrack: tool.drawsInnerTrack, size: 72)
            VStack(alignment: .leading, spacing: 0) {
                header(tool.name)
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 6) {
                    if let status = tool.status {
                        Text(status)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(HeadroomTheme.primaryText)
                    } else {
                        ForEach(Array(tool.rows.prefix(2).enumerated()), id: \.offset) { _, row in
                            LimitRow(row: row)
                        }
                        if let amount = tool.amount {
                            Text(amount)
                                .font(.system(size: 11))
                                .foregroundStyle(HeadroomTheme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 4)
                FooterText(footer: model.footer)
            }
        }
    }

    // MARK: Medium, columns

    /// One column per tracked tool: a 56 pt gauge, the name, the tightest percent and its reset.
    private var columns: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(model.columns) { tool in
                    VStack(spacing: 3) {
                        WidgetGauge(gauge: tool.gauge, drawsInnerTrack: tool.drawsInnerTrack, size: 56)
                            .padding(.bottom, 3)
                        Text(tool.name)
                            .font(.system(size: 11))
                            .foregroundStyle(HeadroomTheme.secondaryText)
                            .lineLimit(1)
                        if let status = tool.status {
                            Text(status)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(HeadroomTheme.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        } else if let row = tool.tightestRow {
                            LimitValue(row: row, size: 17)
                            Text(row.shortDetail)
                                .font(.system(size: 11))
                                .foregroundStyle(HeadroomTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 4)
            HStack {
                FooterText(footer: model.footer)
                Spacer(minLength: 8)
                if !model.isEmpty {
                    DotAndCount(dot: model.dot, count: model.count)
                }
            }
        }
    }

    // MARK: Parts

    /// The tool's short name in gray, with the dot and count on the right.
    private func header(_ name: String) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(HeadroomTheme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 4)
            if !model.isEmpty {
                DotAndCount(dot: model.dot, count: model.count)
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(HeadroomTheme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// The label with the row's 10 pt ring key before it, for tools with two rings (1.1 §14.2).
    private func keyedLabel(_ text: String, row: WidgetToolSummary.Row) -> some View {
        HStack(spacing: 4) {
            if let ring = row.ring {
                WidgetRingKey(ring: ring, severity: row.badge?.severity)
            }
            label(text)
        }
    }
}

/// `Weekly … 89%` over `resets Sun 7 PM`, as in the panel header.
struct LimitRow: View {
    var row: WidgetToolSummary.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let ring = row.ring {
                WidgetRingKey(ring: ring, severity: row.badge?.severity)
                    // Centred on the 13 pt title's lowercase letters.
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4.5 }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HeadroomTheme.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    LimitValue(row: row, size: 13)
                }
                Text(row.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(HeadroomTheme.secondaryText)
                    .lineLimit(1)
            }
        }
    }
}
