import AppKit
import QuartzCore
import Testing
@testable import HeadroomUI

/// Spec §1.1: the working ring expands to 2.6× and fades over 1.6 s, repeating. The live pulse is a
/// Core Animation animation (no SwiftUI update per frame) that only runs while it can be seen.
@MainActor @Suite struct PulsingDotTests {
    @Test func ringGeometryFollowsTheSpec() {
        #expect(PulsingDot.ringDiameter(7, phase: 0) == 7)
        #expect(abs(PulsingDot.ringDiameter(7, phase: 1) - 7 * 2.6) < 1e-9)
        // Ease-out: more than half the growth in the first half of the cycle.
        #expect(PulsingDot.ringDiameter(7, phase: 0.5) > 7 * 1.8)
        #expect(PulsingDot.ringOpacity(phase: 0) == 0.9)
        #expect(PulsingDot.ringOpacity(phase: 1) == 0)
        #expect(abs(PulsingDot.ringOpacity(phase: 0.5) - 0.45) < 1e-9)
    }

    @Test(arguments: [7.0, 6.0, 5.5])
    func ringExtentHoldsTheLargestRingAndKeepsTheDotsPixelAlignment(diameter: CGFloat) {
        let extent = PulsingDot.ringExtent(diameter)
        #expect(extent >= PulsingDot.ringDiameter(diameter, phase: 1) + PulsingDot.ringLineWidth)
        // The ring view is laid out centered on the dot; a whole-point margin on each side puts
        // its origin on the same pixel grid as the dot's, so AppKit's frame rounding can't shift
        // the ring off the dot's center.
        let margin = (extent - diameter) / 2
        #expect(margin == margin.rounded())
        #expect(extent < PulsingDot.ringDiameter(diameter, phase: 1) + PulsingDot.ringLineWidth + 2)
    }

    @Test func pulseAnimationMatchesTheFrozenRing() throws {
        let group = PulseRingView.pulseAnimation(diameter: 7, beginTime: 0)
        #expect(group.duration == 1.6)
        #expect(group.repeatCount == .infinity)
        let parts = Dictionary(uniqueKeysWithValues: (group.animations ?? []).compactMap { animation in
            (animation as? CABasicAnimation).flatMap { basic in basic.keyPath.map { ($0, basic) } }
        })

        let size = try #require(parts["bounds.size"])
        let lineWidth = PulsingDot.ringLineWidth
        #expect((size.fromValue as? NSValue)?.sizeValue == CGSize(width: 7 + lineWidth, height: 7 + lineWidth))
        let grown = PulsingDot.ringDiameter(7, phase: 1) + lineWidth
        #expect((size.toValue as? NSValue)?.sizeValue == CGSize(width: grown, height: grown))
        #expect(size.duration == 1.6)
        // 1 - (1 - t)² is exactly the cubic Bézier (1/3, 2/3) (2/3, 1).
        let easeOut: [Float] = [1.0 / 3, 2.0 / 3, 2.0 / 3, 1]
        #expect(closeEnough(controlPoints(size.timingFunction), easeOut))

        let corner = try #require(parts["cornerRadius"])
        #expect(corner.fromValue as? CGFloat == (7 + lineWidth) / 2)
        #expect(corner.toValue as? CGFloat == grown / 2)
        #expect(corner.duration == 1.6)
        #expect(closeEnough(controlPoints(corner.timingFunction), easeOut))

        let opacity = try #require(parts["opacity"])
        #expect(opacity.fromValue as? Float == 0.9)
        #expect(opacity.toValue as? Float == 0)
        #expect(opacity.duration == 1.6)
        #expect(closeEnough(controlPoints(opacity.timingFunction), controlPoints(CAMediaTimingFunction(name: .linear))))
    }

    @Test func ringViewAnimatesOnlyWhileShown() {
        let view = PulseRingView(diameter: 7)
        #expect(view.frame.size == CGSize(width: PulsingDot.ringExtent(7), height: PulsingDot.ringExtent(7)))
        #expect(!view.isAnimating)

        view.setAnimating(true)
        #expect(view.isAnimating)
        view.setAnimating(true)
        #expect(view.ringLayer.animationKeys()?.count == 1)

        // Not in a window (removed, or the panel closed): nothing runs.
        view.refreshAnimation()
        #expect(!view.isAnimating)

        // At rest the ring is invisible, so a paused pulse leaves no ring behind.
        #expect(view.ringLayer.opacity == 0)
    }

    @Test func ringViewFollowsItsDiameter() {
        let view = PulseRingView(diameter: 7)
        view.setAnimating(true)
        view.diameter = 6
        let group = view.ringLayer.animation(forKey: PulseRingView.animationKey) as? CAAnimationGroup
        let size = group?.animations?.compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "bounds.size" }
        let lineWidth = PulsingDot.ringLineWidth
        #expect((size?.fromValue as? NSValue)?.sizeValue == CGSize(width: 6 + lineWidth, height: 6 + lineWidth))
        #expect(view.ringLayer.borderWidth == lineWidth)
    }

    @Test func pulsesShareOnePhase() {
        // Every dot (pill and panel rows) pulses in step, as the frozen phase formula says.
        let now: CFTimeInterval = 5_000
        let date = Date(timeIntervalSinceReferenceDate: 1.6 * 1_000 + 0.4)
        let begin = PulseRingView.alignedBeginTime(layerTime: now, date: date)
        #expect(abs((now - begin) - 0.4) < 1e-6)
    }

    @Test func ringViewIgnoresClicksAndAccessibility() {
        let view = PulseRingView(diameter: 7)
        #expect(view.hitTest(NSPoint(x: 5, y: 5)) == nil)
        #expect(!view.isAccessibilityElement())
    }

    private func controlPoints(_ function: CAMediaTimingFunction?) -> [Float] {
        guard let function else { return [] }
        var first: [Float] = [0, 0]
        var second: [Float] = [0, 0]
        function.getControlPoint(at: 1, values: &first)
        function.getControlPoint(at: 2, values: &second)
        return first + second
    }

    private func closeEnough(_ a: [Float], _ b: [Float]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-5 }
    }
}
