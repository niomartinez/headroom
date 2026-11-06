import SwiftUI

/// The status dot (spec §1.1). Working: green with a ring that expands to 2.6× and fades over
/// 1.6 s, repeating. Waiting: steady amber. Idle: steady gray. With Differentiate Without Color
/// the waiting dot is a hollow ring: its amber and the working green have almost the same luminance.
///
/// The live ring is a Core Animation animation (`PulseRingView`): SwiftUI does no work per frame,
/// and the animation is removed while its window is hidden or fully covered. With
/// `frozenPulsePhase` set (static renders such as `headroom-render`) the ring is drawn by SwiftUI
/// at that phase instead, with the same geometry.
public struct PulsingDot: View {
    static let period: TimeInterval = 1.6
    static let maxRingScale: CGFloat = 2.6
    public static let ringLineWidth: CGFloat = 1.25
    static let ringPeakOpacity = 0.9

    public var state: DotState
    public var diameter: CGFloat
    private var differentiateWithoutColorOverride: Bool?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.frozenPulsePhase) private var frozenPhase

    public init(state: DotState, diameter: CGFloat = 7, differentiateWithoutColor: Bool? = nil) {
        self.state = state
        self.diameter = diameter
        differentiateWithoutColorOverride = differentiateWithoutColor
    }

    /// How the dot itself is drawn.
    enum Mark: Equatable {
        /// A filled circle.
        case disc
        /// A circle outline around an empty middle.
        case ring
    }

    /// Only the waiting dot changes, and only when color alone must not tell the states apart.
    static func mark(for state: DotState, differentiateWithoutColor: Bool) -> Mark {
        state == .waiting && differentiateWithoutColor ? .ring : .disc
    }

    /// The outline of the `.ring` mark: thick enough to show its color, thin enough to leave the
    /// middle visibly empty (1.75 pt of a 7 pt dot).
    static func markLineWidth(_ diameter: CGFloat) -> CGFloat {
        max(1.25, diameter / 4)
    }

    public var body: some View {
        ZStack {
            if state == .working { pulse }
            mark
                .frame(width: diameter, height: diameter)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var mark: some View {
        let color = HeadroomTheme.color(for: state)
        switch Self.mark(for: state, differentiateWithoutColor: differentiateWithoutColorOverride ?? differentiateWithoutColor) {
        case .disc: Circle().fill(color)
        case .ring: Circle().strokeBorder(color, lineWidth: Self.markLineWidth(diameter))
        }
    }

    @ViewBuilder private var pulse: some View {
        if let frozenPhase {
            ring(phase: frozenPhase)
        } else if !reduceMotion {
            let extent = Self.ringExtent(diameter)
            PulseRing(diameter: diameter)
                .frame(width: extent, height: extent)
                .allowsHitTesting(false)
        }
    }

    private func ring(phase: Double) -> some View {
        Circle()
            .stroke(HeadroomTheme.working, lineWidth: Self.ringLineWidth)
            .frame(width: Self.ringDiameter(diameter, phase: phase), height: Self.ringDiameter(diameter, phase: phase))
            .opacity(Self.ringOpacity(phase: phase))
    }

    /// The ring's diameter (to the middle of its stroke) at `phase` 0...1: ease-out growth from
    /// the dot's size to 2.6×.
    public static func ringDiameter(_ diameter: CGFloat, phase: Double) -> CGFloat {
        let progress = min(1, max(0, phase))
        let eased = 1 - (1 - progress) * (1 - progress)
        return diameter * (1 + (maxRingScale - 1) * eased)
    }

    /// Linear fade from 0.9 to 0 over the cycle.
    public static func ringOpacity(phase: Double) -> Double {
        ringPeakOpacity * (1 - min(1, max(0, phase)))
    }

    /// The square the ring needs at its largest, stroke included, with a whole-point margin
    /// around the dot: the live ring's view is centered on the dot, and AppKit rounds view frames
    /// to pixels, so this keeps its origin on the dot's pixel grid and the ring on the dot's center.
    static func ringExtent(_ diameter: CGFloat) -> CGFloat {
        let largest = ringDiameter(diameter, phase: 1) + ringLineWidth
        return diameter + 2 * ((largest - diameter) / 2).rounded(.up)
    }

    /// 0..<1 position inside the current 1.6 s cycle.
    public static func phase(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        return (t < 0 ? t + period : t) / period
    }
}

/// The live working ring, hosted as an AppKit view so Core Animation runs it.
private struct PulseRing: NSViewRepresentable {
    var diameter: CGFloat

    func makeNSView(context: Context) -> PulseRingView {
        PulseRingView(diameter: diameter)
    }

    func updateNSView(_ view: PulseRingView, context: Context) {
        view.diameter = diameter
    }

    static func dismantleNSView(_ view: PulseRingView, coordinator: ()) {
        view.setAnimating(false)
    }
}

extension EnvironmentValues {
    /// Draws the working pulse frozen at this phase (0...1) instead of animating, for static
    /// snapshots such as `headroom-render`. Nil (the default) animates.
    @Entry public var frozenPulsePhase: Double? = nil
    /// Static renders only (`headroom-render`): draw this session row as hovered, since ImageRenderer can't hover.
    @Entry public var previewHoveredSessionID: String? = nil
    /// Static renders only: draw the panel header as with the limit row of this ring hovered (1.1 §14.2).
    @Entry public var previewHoveredLimitRing: GaugeRing? = nil
}
