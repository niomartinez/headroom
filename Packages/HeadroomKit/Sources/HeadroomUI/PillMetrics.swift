import CoreGraphics

/// The pill's sizes at a given height (1.1 §14.6, Nio's note 8). 1.0's pill is 22 pt tall with an 18 pt gauge, a
/// 7 pt dot and 12 pt text; the app now passes the menu bar's own height minus about 3 pt above and below (Nio's
/// bar is about 30 pt, so a 24 pt pill, the height of a system Live Activity capsule). Everything scales with the
/// height, rounded so rings and dots stay on whole points; at 22 pt every value is 1.0's.
public struct PillMetrics: Sendable, Equatable {
    /// 1.0's height, and the smallest the pill gets.
    public static let minimumHeight: CGFloat = 22
    /// What renders and store screenshots use: a 30 pt menu bar minus 3 pt above and below.
    public static let standardHeight: CGFloat = 24
    /// The app's height for a menu bar `menuBarHeight` points tall: 3 pt of air above and below, never under 22 pt.
    public static func height(forMenuBar menuBarHeight: CGFloat) -> CGFloat {
        max(minimumHeight, (menuBarHeight - 6).rounded(.down))
    }

    public let height: CGFloat
    /// `height / 22`.
    public let scale: CGFloat
    /// The ring gauge: 18 pt at 22, an even number of points so its centre sits on the pixel grid.
    public let gaugeSize: CGFloat
    /// The status dot: 7 pt at 22.
    public let dotDiameter: CGFloat
    /// Count, numbers and moment text: 12 pt at 22; also the moment and needs-you symbols.
    public let fontSize: CGFloat
    /// Left and right of the content: 9 pt at 22.
    public let horizontalPadding: CGFloat
    /// Between the dot group, the gauge and the number: 7 pt at 22.
    public let spacing: CGFloat
    /// Between the dot and the count: 5 pt at 22.
    public let dotSpacing: CGFloat
    /// Between gauges with one gauge per tool: 5 pt at 22.
    public let toolGaugeSpacing: CGFloat
    /// The widest a moment's text gets: 212 pt at 22, so the widened pill stays under about 280 pt whatever the
    /// name's glyphs. The status item is as wide as the pill, and a menu bar with a notch hides an item that no
    /// longer fits.
    public let maxMomentTextWidth: CGFloat
    /// The widest the needs-you rest state's name gets (1.1 §14.4): 88 pt at 22.
    public let maxAttentionNameWidth: CGFloat
    /// The same with one gauge per tool, which already makes the pill wider: 56 pt at 22.
    public let maxAttentionNameWidthPerTool: CGFloat

    public init(height requested: CGFloat = PillMetrics.minimumHeight) {
        let height = max(Self.minimumHeight, requested.isFinite ? requested : Self.minimumHeight)
        let scale = height / Self.minimumHeight
        self.height = height
        self.scale = scale
        gaugeSize = max(18, (18 * scale / 2).rounded() * 2)
        dotDiameter = (7 * scale).rounded()
        fontSize = (12 * scale).rounded()
        horizontalPadding = (9 * scale).rounded()
        spacing = (7 * scale).rounded()
        dotSpacing = (5 * scale).rounded()
        toolGaugeSpacing = (5 * scale).rounded()
        maxMomentTextWidth = (212 * scale).rounded()
        maxAttentionNameWidth = (88 * scale).rounded()
        maxAttentionNameWidthPerTool = (56 * scale).rounded()
    }

    /// The gauge's ring geometry at `gaugeSize`.
    public var gaugeStyle: RingGauge.Style { .pill(size: gaugeSize) }
}
