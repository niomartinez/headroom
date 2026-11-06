import CoreGraphics
import Foundation
import SwiftUI

/// How the menu bar item moves from one pill to the next (1.1 §14.6, Nio's note 7). In 1.0 the text of a moment
/// appeared at once while `NSStatusItem.length`, which AppKit doesn't animate, was still being stepped wider, so the
/// text showed before there was room for it; and every poll could restart the animation.
///
/// A layout or width change uses one transition: capsule, text and gauges share the same progress. The native
/// image compositor reveals full-size, fully opaque content while the capsule changes width; it never asks text
/// to lay out again at an intermediate width. A same-width update within one layout changes at once; with Reduce
/// Motion every change is at once. Pills that arrive during a transition wait, and only the newest is kept.
///
/// Pure: the app composites the old and new content with `progress(_:)` and calls `finished(reduceMotion:)`
/// after the final frame has actually been drawn.
public struct PillMotion<Content: Equatable & Sendable>: Sendable {
    public static var transitionDuration: TimeInterval { 0.3 }

    /// A pill to show: what to draw, its layout, and the item length it needs (its fitting width).
    public struct Target: Sendable, Equatable {
        public var content: Content
        public var mode: PillModel.Mode
        public var width: CGFloat
        /// A new event can animate its symbol even when its text has the same fitting width.
        public var animationID: String?

        public init(content: Content, mode: PillModel.Mode, width: CGFloat, animationID: String? = nil) {
            self.content = content
            self.mode = mode
            self.width = width
            self.animationID = animationID
        }
    }

    /// Transition to `content` and `width` over `duration` (0: at once).
    public struct Step: Sendable, Equatable {
        public var content: Content
        public var width: CGFloat
        public var duration: TimeInterval

        public init(content: Content, width: CGFloat, duration: TimeInterval) {
            self.content = content
            self.width = width
            self.duration = duration
        }
    }

    /// The pill shown, or being moved to.
    public private(set) var shown: Target?
    /// The newest pill that arrived during a transition.
    public private(set) var pending: Target?
    /// A transition with a duration is running: new pills wait.
    public private(set) var isRunning = false

    public init() {}

    /// A new pill. Returns the steps to run now: empty when nothing changed, or when a transition is running (the
    /// pill then waits in `pending`, replacing any older one, and comes from `finished(reduceMotion:)`).
    public mutating func show(_ target: Target, reduceMotion: Bool) -> [Step] {
        guard !isRunning else {
            pending = target
            return []
        }
        guard target != shown else { return [] }
        let steps = shown.map { Self.steps(from: $0, to: target, reduceMotion: reduceMotion) }
            ?? [Step(content: target.content, width: target.width, duration: 0)]
        shown = target
        isRunning = steps.contains { $0.duration > 0 }
        return steps
    }

    /// The app ran every step it was given. Returns the steps for a pill that arrived meanwhile, or none.
    public mutating func finished(reduceMotion: Bool) -> [Step] {
        isRunning = false
        guard let next = pending else { return [] }
        pending = nil
        return show(next, reduceMotion: reduceMotion)
    }

    /// The steps from `from` to `to`.
    public static func steps(from: Target, to: Target, reduceMotion: Bool) -> [Step] {
        let animates = !reduceMotion && (from.mode != to.mode || from.width != to.width
            || (to.animationID != nil && from.animationID != to.animationID))
        return [Step(content: to.content, width: to.width, duration: animates ? transitionDuration : 0)]
    }

    /// How far along a step is at `fraction` (0…1) of its duration: a cubic ease-out, for the item's length.
    public static func progress(_ fraction: Double) -> Double {
        let clamped = min(max(fraction, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }

    /// The SwiftUI animation that follows `progress(_:)` over `duration`, for the content; nil for 0.
    public static func animation(duration: TimeInterval) -> Animation? {
        duration > 0 ? .timingCurve(0.33, 1, 0.68, 1, duration: duration) : nil
    }
}
