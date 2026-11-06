import HeadroomModel
import SwiftUI

/// Which of the gauge's two rings: outer = the longest window (Weekly), inner = the 5-hour window (spec §1.1).
public enum GaugeRing: Sendable, Equatable, Hashable {
    case outer
    case inner
}

/// Two concentric rings (spec §1.1): outer = weekly, inner = 5-hour. Round caps, starting at
/// 12 o'clock and running clockwise over a `#444441` track. Only the outer ring for plans without a 5-hour window
/// (`GaugeModel.showsInnerTrack`, 1.1 §6.1).
///
/// Every ring is drawn in the gauge's own square, around its centre (`RingShape`), never in a smaller frame of its
/// own: a 7 pt inner frame centred in 18 pt lands on a half point, which the layout rounds to the pixel grid on its
/// own, so at 1x and 3x the inner ring sat up to 0.7 px off the outer ring's centre (1.1 §14.6, Nio's note 4).
public struct RingGauge: View {
    /// Ring geometry in a square view box, drawn scaled to `size` points.
    public struct Style: Sendable, Equatable {
        public var size: CGFloat
        public var viewBox: CGFloat
        public var outerRadius: CGFloat
        public var innerRadius: CGFloat
        public var lineWidth: CGFloat

        public init(size: CGFloat, viewBox: CGFloat, outerRadius: CGFloat, innerRadius: CGFloat, lineWidth: CGFloat) {
            self.size = size
            self.viewBox = viewBox
            self.outerRadius = outerRadius
            self.innerRadius = innerRadius
            self.lineWidth = lineWidth
        }

        /// The 18 pt menu bar gauge of the 1.0 22 pt pill.
        public static let pill = Style(size: 18, viewBox: 18, outerRadius: 7, innerRadius: 3.5, lineWidth: 2)
        /// The 72 pt panel header gauge (a 64-unit view box).
        public static let panel = Style(size: 72, viewBox: 64, outerRadius: 26, innerRadius: 17, lineWidth: 5)
        /// The 24 pt gauge of the panel's compact tool rows (1.1 §6.3).
        public static let compact = Style(size: 24, viewBox: 24, outerRadius: 9.5, innerRadius: 5, lineWidth: 2.5)

        /// The pill's gauge at `size` points: the 18-unit view box scaled (1.1 §14.6, taller pill).
        public static func pill(size: CGFloat) -> Style {
            Style(size: size, viewBox: pill.viewBox, outerRadius: pill.outerRadius, innerRadius: pill.innerRadius,
                  lineWidth: pill.lineWidth)
        }

        var scale: CGFloat { viewBox > 0 ? size / viewBox : 1 }

        func radius(_ ring: GaugeRing) -> CGFloat {
            (ring == .outer ? outerRadius : innerRadius) * scale
        }
    }

    /// The ring that isn't emphasized dims to this while a limit row is hovered (1.1 §14.2).
    public static let dimmedRingOpacity = 0.28

    public var gauge: GaugeModel
    public var style: Style
    /// The ring a hovered limit row names (1.1 §14.2): the other one dims to `dimmedRingOpacity`. Nil: both at
    /// full strength.
    public var emphasis: GaugeRing?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(gauge: GaugeModel, style: Style, emphasis: GaugeRing? = nil) {
        self.gauge = gauge
        self.style = style
        self.emphasis = emphasis
    }

    /// 1 for the emphasized ring or with nothing emphasized; `dimmedRingOpacity` for the other.
    public static func ringOpacity(_ ring: GaugeRing, emphasis: GaugeRing?) -> Double {
        guard let emphasis, emphasis != ring else { return 1 }
        return dimmedRingOpacity
    }

    public var body: some View {
        ZStack {
            ring(gauge.outer, which: .outer)
            if gauge.showsInnerTrack {
                ring(gauge.inner, which: .inner)
            }
        }
        .frame(width: style.size, height: style.size)
        .opacity(gauge.isStale ? HeadroomTheme.staleOpacity : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: emphasis)
        .accessibilityHidden(true)
    }

    private func ring(_ value: GaugeModel.Ring?, which: GaugeRing) -> some View {
        let radius = style.radius(which)
        let stroke = StrokeStyle(lineWidth: style.lineWidth * style.scale, lineCap: .round)
        return ZStack {
            RingShape(radius: radius).stroke(HeadroomTheme.track, style: stroke)
            if let value, value.fraction > 0 {
                RingShape(radius: radius, fraction: value.fraction)
                    .stroke(HeadroomTheme.color(for: value.severity), style: stroke)
            }
        }
        .opacity(emphasis == nil ? 1 : Self.ringOpacity(which, emphasis: emphasis))
    }
}

/// The tool's symbol on its gauge, so gauges side by side tell their tools apart (Nio, 2026-10-02). It fills the
/// gauge's empty middle when that is at least `minimumMiddle` wide. A small two-ring gauge's middle is too small, so
/// the symbol is a badge over the outer ring's upper left instead. The ring only reaches there past about 78 %,
/// where the pill shows the percentage beside the gauge.
struct GaugeToolIcon: View {
    static let minimumMiddle: CGFloat = 10
    static let largestSymbol: CGFloat = 16

    let tool: ToolID
    let gauge: GaugeModel
    let style: RingGauge.Style
    /// What the gauge is drawn on: the badge cuts the rings out in this color.
    let background: Color

    var body: some View {
        let middle = 2 * (style.radius(gauge.showsInnerTrack ? .inner : .outer) - style.lineWidth * style.scale / 2)
        if middle >= Self.minimumMiddle {
            symbol(size: min(middle * 0.6, Self.largestSymbol))
        } else {
            let diameter = style.size / 2
            symbol(size: diameter * 0.65)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(background))
                .offset(x: -style.size * 0.36, y: -style.size * 0.36)
        }
    }

    private func symbol(size: CGFloat) -> some View {
        Image(systemName: SessionToolIcon.symbol(for: tool))
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(SessionToolIcon.tint(for: tool))
            .opacity(gauge.isStale ? HeadroomTheme.staleOpacity : 1)
            .accessibilityHidden(true)
    }
}

/// A circle, or the part of it from 12 o'clock clockwise to `fraction`, of `radius` around the centre of the rect
/// it is drawn in. Rings of one gauge all draw in the gauge's rect, so they share one centre to the pixel.
public struct RingShape: Shape {
    public var radius: CGFloat
    /// 0...1 of the circle, clockwise from 12 o'clock.
    public var fraction: Double

    public init(radius: CGFloat, fraction: Double = 1) {
        self.radius = radius
        self.fraction = fraction
    }

    public func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        let clamped = min(1, max(0, fraction))
        if clamped >= 1 {
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        } else if clamped > 0 {
            // In a flipped (y down) space, increasing angles run clockwise on screen: `clockwise: false`.
            path.addArc(
                center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * clamped),
                clockwise: false
            )
        }
        return path
    }
}
