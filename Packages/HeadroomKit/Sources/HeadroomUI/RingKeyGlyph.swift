import SwiftUI

/// Which ring a limit row is (1.1 §14.2, Nio's note 2): a miniature of the gauge with only that row's ring lit,
/// before "Weekly" (outer) and "5-hour" (inner). The shape carries the meaning, not the color, so it still reads at
/// warning and critical, when stale, with Differentiate Without Color and in accented widgets. The lit ring takes
/// the row's severity color, like its arc; the other ring is the track.
///
/// 12 pt in the panel header, 10 pt in compact tool rows (two-window tools only) and the Limits widgets.
public struct RingKeyGlyph: View {
    /// The panel header's glyph.
    public static let size: CGFloat = 12
    /// Compact tool rows and widgets.
    public static let compactSize: CGFloat = 10
    /// Geometry at 12 pt: outer radius 5, inner 2.25, line 1.5 (the outer ring's stroke reaches the box's edge).
    static let outerRadius: CGFloat = 5
    static let innerRadius: CGFloat = 2.25
    static let lineWidth: CGFloat = 1.5

    public var ring: GaugeRing
    public var color: Color
    public var trackColor: Color
    public var size: CGFloat

    public init(ring: GaugeRing, color: Color, trackColor: Color = HeadroomTheme.track, size: CGFloat = RingKeyGlyph.size) {
        self.ring = ring
        self.color = color
        self.trackColor = trackColor
        self.size = size
    }

    public var body: some View {
        ZStack {
            Self.stroked(ring == .outer ? .inner : .outer, color: trackColor, size: size)
            Self.stroked(ring, color: color, size: size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// One of the glyph's rings at `size`, stroked in `color`, around the centre of a `size` square: for callers
    /// that style the lit ring themselves (the widgets make it accentable).
    public static func stroked(_ which: GaugeRing, color: Color, size: CGFloat) -> some View {
        let scale = size / Self.size
        let radius = (which == .outer ? outerRadius : innerRadius) * scale
        return RingShape(radius: radius)
            .stroke(color, lineWidth: lineWidth * scale)
            .frame(width: size, height: size)
    }
}
