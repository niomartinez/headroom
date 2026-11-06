import AppKit
import HeadroomUI
import Testing

@MainActor
@Suite("Native pill animation", .serialized)
struct StatusItemAnimatorTests {
    @Test func aStoppedDisplayLinkStillDrawsTheFinalFrameAndCompletes() {
        let item = NSStatusBar.system.statusItem(withLength: 340)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let animator = StatusItemLengthAnimator(statusItem: item)
        var completed = 0
        var lastProgress: Double?
        animator.animate(to: 80, duration: 0.05) { _, progress in
            lastProgress = progress
        } completion: { completed += 1 }
        // Model a sleeping/inactive display: no frame callback will finish this transition.
        animator.displayLink?.invalidate()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        #expect(completed == 1)
        #expect(lastProgress == 1)
        #expect(item.length == 80)
        #expect(!animator.isAnimating)
        animator.render(elapsed: 1)
        #expect(completed == 1)
    }

    @Test func replacingAnAnimationCancelsItsOldCompletionDeadline() {
        let item = NSStatusBar.system.statusItem(withLength: 80)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let animator = StatusItemLengthAnimator(statusItem: item)
        var oldCompleted = 0
        var newCompleted = 0
        animator.animate(to: 340, duration: 0.01) { _, _ in } completion: { oldCompleted += 1 }
        animator.animate(to: 120, duration: 10) { _, _ in } completion: { newCompleted += 1 }
        animator.displayLink?.invalidate()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        #expect(oldCompleted == 0)
        #expect(newCompleted == 0)
        #expect(animator.isAnimating)
        animator.render(elapsed: 10)
        #expect(newCompleted == 1)
    }

    @Test(arguments: [false, true])
    func intermediateFramesKeepOneCanvasAndCompleteAfterTheLastFrame(shrinking: Bool) {
        let start: CGFloat = shrinking ? 340 : 80
        let end: CGFloat = shrinking ? 80 : 340
        let item = NSStatusBar.system.statusItem(withLength: start)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let animator = StatusItemLengthAnimator(statusItem: item)
        var widths: [CGFloat] = []
        var progress: [Double] = []
        var completed = 0
        animator.animate(to: end, duration: 0.3) { width, fraction in
            widths.append(width)
            progress.append(fraction)
        } completion: {
            #expect(widths.last == end)
            #expect(progress.last == 1)
            completed += 1
        }
        for elapsed in [0.0, 0.05, 0.1, 0.2, 0.29] {
            animator.render(elapsed: elapsed)
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                #expect(item.length == max(start, end))
                #expect(completed == 0)
            }
        }
        animator.render(elapsed: 0.3)
        animator.render(elapsed: 0.5)
        #expect(completed == 1)
        #expect(item.length == end)
        #expect(progress == progress.sorted())
        #expect(widths == widths.sorted(by: shrinking ? (>) : (<)))
        #expect(!animator.isAnimating)
    }

    @Test func noDurationCompletesSynchronously() {
        let item = NSStatusBar.system.statusItem(withLength: 80)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let animator = StatusItemLengthAnimator(statusItem: item)
        var events: [String] = []
        animator.animate(to: 340, duration: 0) { width, progress in
            #expect(width == 340 && progress == 1 && item.length == 340)
            events.append("draw")
        } completion: { events.append("complete") }
        #expect(events == ["draw", "complete"])
        #expect(!animator.isAnimating)
    }
}
