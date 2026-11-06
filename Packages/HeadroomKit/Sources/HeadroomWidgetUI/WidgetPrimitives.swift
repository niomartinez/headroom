import HeadroomModel
import HeadroomUI
import SwiftUI
import WidgetKit

// Small pieces the widget layouts share. Widgets can't host AppKit views, hover or tooltips (§5.6), so these are
// plain SwiftUI: a static dot instead of `PulsingDot`, and a gauge that can draw one ring without an inner track.

/// Whether the system draws the widget see-through (§5.7): accented or vibrant, or without its container
/// background (dimmed on the desktop). Colors can't carry meaning then, so tracks become translucent, arcs join
/// the accent group and severity gets a symbol.
struct SeeThrough {
    static func isOn(renderingMode: WidgetRenderingMode, showsBackground: Bool) -> Bool {
        renderingMode != .fullColor || !showsBackground
    }
}

/// The widget's ring gauge: outer = the longest window, inner = 5-hour. Without an inner track (`drawsInnerTrack`
/// false) only the outer ring is drawn (§6.1). Geometry follows the panel gauge (64-unit view box) at 40 pt and up,
/// the compact rows' (24-unit view box) below.
struct WidgetGauge: View {
    var gauge: GaugeModel
    var drawsInnerTrack: Bool
    var size: CGFloat

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var geometry: (viewBox: CGFloat, outer: CGFloat, inner: CGFloat, lineWidth: CGFloat) {
        size >= 40 ? (64, 26, 17, 5) : (24, 9.5, 5, 2.5)
    }

    var body: some View {
        let seeThrough = SeeThrough.isOn(renderingMode: renderingMode, showsBackground: showsBackground)
        ZStack {
            ring(gauge.outer, radius: geometry.outer, seeThrough: seeThrough)
            if drawsInnerTrack {
                ring(gauge.inner, radius: geometry.inner, seeThrough: seeThrough)
            }
        }
        .frame(width: size, height: size)
        .opacity(gauge.isStale ? HeadroomTheme.staleOpacity : 1)
        .accessibilityHidden(true)
    }

    /// Drawn in the gauge's own square around its centre (`RingShape`), so both rings share one centre to the
    /// pixel (1.1 §14.6).
    private func ring(_ value: GaugeModel.Ring?, radius: CGFloat, seeThrough: Bool) -> some View {
        let scale = size / geometry.viewBox
        let stroke = StrokeStyle(lineWidth: geometry.lineWidth * scale, lineCap: .round)
        return ZStack {
            // The opaque #444441 track would be tinted solid in accented mode: see-through, it's the primary color
            // at 22 % (§5.7).
            RingShape(radius: radius * scale).stroke(seeThrough ? Color.primary.opacity(0.22) : HeadroomTheme.track, style: stroke)
            if let value, value.fraction > 0 {
                RingShape(radius: radius * scale, fraction: value.fraction)
                    .stroke(HeadroomTheme.color(for: value.severity), style: stroke)
                    .widgetAccentable()
            }
        }
    }
}

/// The 10 pt ring key before a limit's label (1.1 §14.2). See-through, the unlit ring is the primary color at 22 %
/// like the gauge's track, and the lit ring joins the accent group.
struct WidgetRingKey: View {
    var ring: GaugeRing
    var severity: Severity?

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    var body: some View {
        let seeThrough = SeeThrough.isOn(renderingMode: renderingMode, showsBackground: showsBackground)
        let size = RingKeyGlyph.compactSize
        ZStack {
            RingKeyGlyph.stroked(
                ring == .outer ? .inner : .outer, color: seeThrough ? Color.primary.opacity(0.22) : HeadroomTheme.track, size: size
            )
            RingKeyGlyph.stroked(ring, color: severity.map(HeadroomTheme.color(for:)) ?? HeadroomTheme.secondaryText, size: size)
                .widgetAccentable()
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The session dot without its pulse: green working, amber waiting, gray idle. With Differentiate Without Color the
/// waiting dot is a ring, as in the panel.
struct StaticDot: View {
    var state: DotState
    var diameter: CGFloat = 6

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        let color = HeadroomTheme.color(for: state)
        Group {
            if state == .waiting && differentiateWithoutColor {
                Circle().strokeBorder(color, lineWidth: max(1.25, diameter / 4))
            } else {
                Circle().fill(color)
            }
        }
        .frame(width: diameter, height: diameter)
        .widgetAccentable(state != .idle)
        .accessibilityHidden(true)
    }
}

/// The dot and the active count, as in the pill: `● 3`.
struct DotAndCount: View {
    var dot: DotState
    var count: Int?

    var body: some View {
        HStack(spacing: 4) {
            StaticDot(state: dot)
            if let count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(HeadroomTheme.primaryText)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A limit's value in its severity color. See-through, color says nothing, so from 75 % a warning symbol stands
/// before it and the weight goes up (§5.7).
struct LimitValue: View {
    var row: WidgetToolSummary.Row
    var size: CGFloat
    var weight: Font.Weight = .semibold

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    var body: some View {
        let seeThrough = SeeThrough.isOn(renderingMode: renderingMode, showsBackground: showsBackground)
        let severity = row.badge?.severity ?? .normal
        let marked = seeThrough && severity != .normal
        HStack(spacing: size * 0.18) {
            if marked {
                Image(systemName: severity == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: size * 0.62, weight: .bold))
                    .widgetAccentable()
            }
            Text(row.value)
                .font(.system(size: size, weight: marked ? .bold : weight).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(row.badge.map { HeadroomTheme.color(for: $0.severity) } ?? HeadroomTheme.secondaryText)
    }
}

/// The footer line: gray, amber for "Sample data", bright for what needs the user.
struct FooterText: View {
    var footer: WidgetFooter

    var body: some View {
        Text(footer.text)
            .font(.system(size: 11, weight: footer.tone == .plain ? .regular : .medium))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private var color: Color {
        switch footer.tone {
        case .plain: HeadroomTheme.secondaryText
        case .sample: HeadroomTheme.warning
        case .attention: HeadroomTheme.primaryText
        }
    }
}

/// One tool in a compact row (1.1 §6.3): a 24 pt gauge, the name, then one line per limit (label, percent, detail),
/// or the status. The panel's compact rows are S5's; this is the widgets' own copy of the same grid, narrowed to a
/// widget's width.
struct CompactToolRow: View {
    static let gaugeSize: CGFloat = 24
    static let nameWidth: CGFloat = 58
    static let labelWidth: CGFloat = 46
    static let percentWidth: CGFloat = 34
    static let lineHeight: CGFloat = 16

    var summary: WidgetToolSummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            WidgetGauge(gauge: summary.gauge, drawsInnerTrack: summary.drawsInnerTrack, size: Self.gaugeSize)
                .frame(height: max(Self.gaugeSize, Self.lineHeight * CGFloat(max(1, lineCount))), alignment: .center)
            HStack(alignment: .top, spacing: 0) {
                Text(summary.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HeadroomTheme.primaryText)
                    .lineLimit(1)
                    .frame(width: Self.nameWidth, height: Self.lineHeight, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    if let status = summary.status {
                        line(status)
                    } else {
                        ForEach(Array(summary.rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 0) {
                                Text(row.title)
                                    .font(.system(size: 11))
                                    .foregroundStyle(HeadroomTheme.secondaryText)
                                    .lineLimit(1)
                                    .frame(width: Self.labelWidth, alignment: .leading)
                                LimitValue(row: row, size: 12)
                                    .frame(width: Self.percentWidth, alignment: .trailing)
                                Text(row.detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(HeadroomTheme.secondaryText)
                                    .lineLimit(1)
                                    .padding(.leading, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: Self.lineHeight)
                        }
                        if let amount = summary.amount {
                            line(amount)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([summary.name] + (summary.status.map { [$0] } ?? summary.rows.map(\.accessibilityText)))
            .joined(separator: ", "))
    }

    private var lineCount: Int {
        summary.status != nil ? 1 : summary.rows.count + (summary.amount == nil ? 0 : 1)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(HeadroomTheme.secondaryText)
            .lineLimit(1)
            .frame(height: Self.lineHeight, alignment: .leading)
    }
}
