import CoreGraphics
import Foundation
import HeadroomUI

/// Geometry for the native pill (spec §1.1, 1.1 §14.6). The visible capsule follows `PillMotion`'s curve inside
/// a fixed native image canvas; the menu-bar item's reserved length changes only at the transition boundaries.
enum StatusItemMotion {
    /// `false` means jump straight to `target`: a step without a duration (Reduce Motion, or a change within one
    /// layout), an item that hasn't been sized yet (`variableLength` is -1), or a change under a point.
    static func animates(from start: CGFloat, to target: CGFloat, duration: TimeInterval) -> Bool {
        duration > 0 && start > 0 && abs(start - target) >= 1
    }

    /// The length `fraction` (0…1 of the step's duration) of the way from `start` to `target`: `PillMotion`'s cubic
    /// ease-out, the curve the pill's content animates on.
    static func length(from start: CGFloat, to target: CGFloat, fraction: Double) -> CGFloat {
        start + (target - start) * PillMotion<Int>.progress(fraction)
    }

    /// The pill's height in a menu bar `menuBarHeight` points tall (the status item's window is as tall as the menu
    /// bar): 3 pt of air above and below, never under 22 pt (1.1 §14.6). 22 pt while the height isn't known.
    static func pillHeight(menuBarHeight: CGFloat?) -> CGFloat {
        guard let menuBarHeight, menuBarHeight.isFinite, menuBarHeight > 0 else { return PillMetrics.minimumHeight }
        return PillMetrics.height(forMenuBar: menuBarHeight)
    }

    /// One image is shared by every menu bar. Size it for the shortest bar, independent of the focused display.
    static func sharedPillHeight(menuBarHeights: [CGFloat]) -> CGFloat {
        pillHeight(menuBarHeight: menuBarHeights.filter { $0.isFinite && $0 > 0 }.min())
    }

    /// One image is shared by the displays, so it must respect the narrowest connected lane.
    static func widthBudget(lanes: [CGFloat]) -> CGFloat? {
        lanes.filter { $0.isFinite && $0 > 0 }.min()
    }
}

/// Runs `PillMotion`'s steps one after another (1.1 §14.6). Pure: the status item draws each step it gets, and calls
/// `stepFinished` when the step's duration has passed (at once for a step without one).
struct PillChoreography<Content: Equatable & Sendable> {
    typealias Step = PillMotion<Content>.Step

    private(set) var motion = PillMotion<Content>()
    /// The steps still to run for the pill being moved to.
    private(set) var remaining: [Step] = []

    /// A new pill: the step to draw now, or nil when nothing changed or a transition is running (the pill then waits,
    /// and only the newest waiting pill is kept).
    mutating func show(_ target: PillMotion<Content>.Target, reduceMotion: Bool) -> Step? {
        start(motion.show(target, reduceMotion: reduceMotion))
    }

    /// The step drawn last is done: the next one, else the first step towards a pill that arrived meanwhile, else nil.
    mutating func stepFinished(reduceMotion: Bool) -> Step? {
        guard remaining.isEmpty else { return remaining.removeFirst() }
        return start(motion.finished(reduceMotion: reduceMotion))
    }

    private mutating func start(_ steps: [Step]) -> Step? {
        guard !steps.isEmpty else { return nil }
        remaining = Array(steps.dropFirst())
        return steps[0]
    }
}

/// Advances only after the renderer presents the final frame. New targets coalesce while a transition runs;
/// there is no second timer that can replace an animation before its last frame.
@MainActor
final class PillStepper<Content: Equatable & Sendable> {
    typealias Step = PillMotion<Content>.Step
    typealias Draw = (Step, @escaping @MainActor () -> Void) -> Void

    private var choreography = PillChoreography<Content>()
    private let draw: Draw
    private let reduceMotion: () -> Bool
    private var generation = 0

    init(draw: @escaping Draw, reduceMotion: @escaping () -> Bool) {
        self.draw = draw
        self.reduceMotion = reduceMotion
    }

    func show(_ target: PillMotion<Content>.Target) {
        guard let step = choreography.show(target, reduceMotion: reduceMotion()) else { return }
        run(step)
    }

    private func run(_ step: Step) {
        generation += 1
        let current = generation
        draw(step) { [weak self] in
            guard let self, self.generation == current else { return }
            self.generation += 1
            if let next = self.choreography.stepFinished(reduceMotion: self.reduceMotion()) {
                self.run(next)
            }
        }
    }
}
