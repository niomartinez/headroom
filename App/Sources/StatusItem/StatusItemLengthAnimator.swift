import AppKit
import HeadroomUI
import QuartzCore

/// Reserves menu-bar space once, then animates the pill inside a fixed image canvas. Changing the native item's
/// length every frame makes its asynchronous window positioning fight with the image's changing dimensions.
@MainActor
final class StatusItemLengthAnimator: NSObject {
    private let statusItem: NSStatusItem
    private(set) var displayLink: CADisplayLink?
    private var completionTimer: Timer?
    private var start: CGFloat = 0
    private var target: CGFloat = 0
    private var began: TimeInterval = 0
    private var duration: TimeInterval = 0
    private var draw: ((CGFloat, Double) -> Void)?
    private var completion: (() -> Void)?
    private(set) var isAnimating = false

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
    }

    /// `width` is the visible capsule width including the native image inset. `statusItem.length` stays at the
    /// larger endpoint until completion, so every intermediate image has the same dimensions.
    func animate(to length: CGFloat, duration: TimeInterval,
                 draw: @escaping @MainActor (CGFloat, Double) -> Void,
                 completion: @escaping @MainActor () -> Void) {
        displayLink?.invalidate()
        displayLink = nil
        completionTimer?.invalidate()
        completionTimer = nil
        start = statusItem.length
        target = length
        self.duration = duration
        self.draw = draw
        self.completion = completion
        guard duration > 0, start > 0,
              let screen = statusItem.button?.window?.screen ?? NSScreen.main else {
            finish()
            return
        }
        isAnimating = true
        statusItem.length = max(start, target)
        draw(start, 0)
        began = CACurrentMediaTime()
        // Drive frames from the screen even when a menu-bar manager hides the button mid-transition.
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        displayLink = link
        link.add(to: .main, forMode: .common)
        // A display link can stop delivering frames when its screen sleeps or becomes inactive.
        // Finish on the main run loop as well, so pending snapshot changes cannot remain queued forever.
        let timer = Timer(timeInterval: duration + 0.1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        completionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func tick(_ link: CADisplayLink) {
        render(elapsed: link.targetTimestamp - began)
    }

    /// Also used by deterministic native tests: the last frame and its completion belong to the same clock.
    func render(elapsed: TimeInterval) {
        guard isAnimating else { return }
        let fraction = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : elapsed / duration
        guard fraction < 1 else {
            finish()
            return
        }
        draw?(StatusItemMotion.length(from: start, to: target, fraction: fraction), PillMotion<Int>.progress(fraction))
    }

    private func finish() {
        displayLink?.invalidate()
        displayLink = nil
        completionTimer?.invalidate()
        completionTimer = nil
        isAnimating = false
        let finalDraw = draw
        let finished = completion
        draw = nil
        completion = nil
        statusItem.length = target
        finalDraw?(target, 1)
        finished?()
    }
}
