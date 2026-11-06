import AppKit
import QuartzCore

/// The working dot's ring (spec §1.1) as a Core Animation animation: the ring grows from the dot's
/// size to 2.6× (ease-out) while fading from 0.9 to 0 (linear), every 1.6 s.
///
/// Core Animation interpolates the frames itself, so the app does no per-frame work (the earlier
/// `TimelineView` re-ran SwiftUI 30 times a second while any session worked). The animation only
/// runs while the view is in a window that is at least partly visible; hiding or covering the menu
/// bar or panel removes it, and it comes back when the window shows again. All rings share one
/// phase, the one `PulsingDot.phase(at:)` gives for the current time.
final class PulseRingView: NSView {
    static let animationKey = "headroom.pulse"

    /// The ring. Its model opacity is 0, so it is invisible whenever the animation isn't running.
    let ringLayer = CALayer()

    /// The dot's diameter. The view should be `PulsingDot.ringExtent(diameter)` square (SwiftUI
    /// frames it so); the ring stays centered in whatever size it gets.
    var diameter: CGFloat {
        didSet {
            guard diameter != oldValue else { return }
            applyGeometry()
            if isAnimating {
                setAnimating(false)
                setAnimating(true)
            }
        }
    }

    init(diameter: CGFloat) {
        self.diameter = diameter
        super.init(frame: CGRect(origin: .zero, size: Self.size(for: diameter)))
        wantsLayer = true
        ringLayer.opacity = 0
        ringLayer.borderColor = HeadroomTheme.workingCGColor
        ringLayer.backgroundColor = nil
        applyGeometry()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PulseRingView is created in code")
    }

    var isAnimating: Bool {
        ringLayer.animation(forKey: Self.animationKey) != nil
    }

    /// Starts or stops the pulse; starting an already running pulse keeps it as it is.
    func setAnimating(_ animating: Bool) {
        guard animating != isAnimating else { return }
        if animating {
            attachRing()
            let begin = Self.alignedBeginTime(layerTime: ringLayer.convertTime(CACurrentMediaTime(), from: nil), date: Date())
            ringLayer.add(Self.pulseAnimation(diameter: diameter, beginTime: begin), forKey: Self.animationKey)
        } else {
            ringLayer.removeAnimation(forKey: Self.animationKey)
        }
    }

    /// Runs the pulse exactly while the view can be seen.
    func refreshAnimation() {
        setAnimating(isShown)
    }

    /// In a window that is on screen and not fully covered, and not hidden itself.
    private var isShown: Bool {
        guard let window, !isHiddenOrHasHiddenAncestor else { return false }
        return window.occlusionState.contains(.visible)
    }

    // MARK: Animation

    /// The pulse, one 1.6 s cycle repeated forever, starting at `beginTime` (layer time).
    static func pulseAnimation(diameter: CGFloat, beginTime: CFTimeInterval) -> CAAnimationGroup {
        let lineWidth = PulsingDot.ringLineWidth
        let start = PulsingDot.ringDiameter(diameter, phase: 0) + lineWidth
        let end = PulsingDot.ringDiameter(diameter, phase: 1) + lineWidth
        // 1 - (1 - t)², the curve `PulsingDot.ringDiameter` uses, is exactly this cubic Bézier.
        let easeOut = CAMediaTimingFunction(controlPoints: 1.0 / 3, 2.0 / 3, 2.0 / 3, 1)

        let size = CABasicAnimation(keyPath: "bounds.size")
        size.fromValue = NSValue(size: CGSize(width: start, height: start))
        size.toValue = NSValue(size: CGSize(width: end, height: end))
        size.timingFunction = easeOut

        let corner = CABasicAnimation(keyPath: "cornerRadius")
        corner.fromValue = start / 2
        corner.toValue = end / 2
        corner.timingFunction = easeOut

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = Float(PulsingDot.ringOpacity(phase: 0))
        opacity.toValue = Float(PulsingDot.ringOpacity(phase: 1))
        opacity.timingFunction = CAMediaTimingFunction(name: .linear)

        let parts = [size, corner, opacity]
        for part in parts {
            part.duration = PulsingDot.period
        }
        let group = CAAnimationGroup()
        group.animations = parts
        group.duration = PulsingDot.period
        group.repeatCount = .infinity
        group.beginTime = beginTime
        group.isRemovedOnCompletion = false
        return group
    }

    /// A begin time that puts the cycle at the phase `PulsingDot.phase(at: date)`, so every ring
    /// pulses in step (and in step with the frozen renders).
    static func alignedBeginTime(layerTime: CFTimeInterval, date: Date) -> CFTimeInterval {
        layerTime - PulsingDot.phase(at: date) * PulsingDot.period
    }

    // MARK: Layout

    private static func size(for diameter: CGFloat) -> CGSize {
        let extent = PulsingDot.ringExtent(diameter)
        return CGSize(width: extent, height: extent)
    }

    /// The ring at rest: dot-sized, stroke centered on the dot's edge like SwiftUI's `stroke`.
    private func applyGeometry() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = PulsingDot.ringDiameter(diameter, phase: 0) + PulsingDot.ringLineWidth
        ringLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        ringLayer.cornerRadius = side / 2
        ringLayer.borderWidth = PulsingDot.ringLineWidth
        ringLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    /// Keeps the ring in this view's current backing layer.
    private func attachRing() {
        guard let layer, ringLayer.superlayer !== layer else { return }
        layer.addSublayer(ringLayer)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        applyGeometry()
    }

    override func layout() {
        super.layout()
        attachRing()
        applyGeometry()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        ringLayer.contentsScale = window?.backingScaleFactor ?? 2
    }

    // MARK: Visibility

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            // Selector-based observers are dropped automatically when the view goes away.
            NotificationCenter.default.addObserver(
                self, selector: #selector(occlusionChanged(_:)),
                name: NSWindow.didChangeOcclusionStateNotification, object: window
            )
            ringLayer.contentsScale = window.backingScaleFactor
        }
        attachRing()
        refreshAnimation()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        refreshAnimation()
    }

    override func viewDidHide() {
        super.viewDidHide()
        refreshAnimation()
    }

    @objc private func occlusionChanged(_ notification: Notification) {
        refreshAnimation()
    }

    // MARK: Inert

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func isAccessibilityElement() -> Bool { false }
}
