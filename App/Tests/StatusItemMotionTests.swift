import CoreGraphics
import Foundation
import HeadroomUI
import Testing

@Suite struct StatusItemMotionTests {
    @Test func aStepWithADurationSlidesTheLength() {
        #expect(StatusItemMotion.animates(from: 60, to: 160, duration: 0.3))
        #expect(StatusItemMotion.animates(from: 160, to: 60, duration: 0.3))
    }

    /// Reduce Motion, or a change within one layout: `PillMotion` gives a step without a duration, and the length
    /// jumps (F35).
    @Test func aStepWithoutADurationJumps() {
        #expect(!StatusItemMotion.animates(from: 60, to: 160, duration: 0))
    }

    /// `NSStatusItem.variableLength` (-1): the item hasn't been sized yet, nothing to animate from.
    @Test func anUnsizedItemJumps() {
        #expect(!StatusItemMotion.animates(from: -1, to: 160, duration: 0.3))
        #expect(!StatusItemMotion.animates(from: 0, to: 160, duration: 0.3))
    }

    @Test func aChangeUnderOnePointJumps() {
        #expect(!StatusItemMotion.animates(from: 60, to: 60.5, duration: 0.3))
    }

    /// The same cubic ease-out as the pill's content (`PillMotion.progress`).
    @Test func theLengthEasesOut() {
        #expect(StatusItemMotion.length(from: 60, to: 160, fraction: 0) == 60)
        #expect(StatusItemMotion.length(from: 60, to: 160, fraction: 1) == 160)
        #expect(StatusItemMotion.length(from: 60, to: 160, fraction: 0.5) == 147.5)
        #expect(StatusItemMotion.length(from: 60, to: 160, fraction: 2) == 160)
    }

    /// The menu bar's height minus 6 pt, at least 22 pt (1.1 §14.6): 1.0's 22 pt in a 24 pt bar, 24 pt in Nio's
    /// 30 pt bar.
    @Test func thePillIsAsTallAsTheMenuBarAllows() {
        #expect(StatusItemMotion.pillHeight(menuBarHeight: 24) == 22)
        #expect(StatusItemMotion.pillHeight(menuBarHeight: 30) == 24)
        #expect(StatusItemMotion.pillHeight(menuBarHeight: 33.5) == 27)
        #expect(StatusItemMotion.pillHeight(menuBarHeight: 22) == 22)
    }

    @Test func anUnknownMenuBarHeightKeepsThe22PointPill() {
        #expect(StatusItemMotion.pillHeight(menuBarHeight: nil) == 22)
        #expect(StatusItemMotion.pillHeight(menuBarHeight: 0) == 22)
        #expect(StatusItemMotion.pillHeight(menuBarHeight: .infinity) == 22)
        #expect(StatusItemMotion.pillHeight(menuBarHeight: .nan) == 22)
    }
}

/// The status item runs `PillMotion`'s steps one after another (1.1 §14.6).
@Suite struct PillChoreographyTests {
    private typealias Motion = PillMotion<String>

    private let normal = Motion.Target(content: "dot 2", mode: .normal, width: 60)
    private let moment = Motion.Target(content: "harbor needs you", mode: .moment, width: 180)
    private let attention = Motion.Target(content: "(!) harbor", mode: .attention, width: 120)

    /// Every step until the choreography has nothing left, finishing each as the status item would.
    private func drain(_ first: Motion.Step?, _ choreography: inout PillChoreography<String>) -> [Motion.Step] {
        var steps: [Motion.Step] = []
        var next = first
        while let step = next {
            steps.append(step)
            next = choreography.stepFinished(reduceMotion: false)
        }
        return steps
    }

    @Test func theFirstPillShowsAtOnce() {
        var choreography = PillChoreography<String>()
        let step = choreography.show(normal, reduceMotion: false)
        #expect(step == Motion.Step(content: "dot 2", width: 60, duration: 0))
        #expect(choreography.stepFinished(reduceMotion: false) == nil)
    }

    /// Growing: content and width transition together.
    @Test func growingUsesOneCoordinatedTransition() {
        var choreography = PillChoreography<String>()
        _ = choreography.show(normal, reduceMotion: false)
        let first = choreography.show(moment, reduceMotion: false)
        let steps = drain(first, &choreography)
        #expect(steps.map(\.width) == [180])
        #expect(steps.map(\.content) == ["harbor needs you"])
        #expect(steps.allSatisfy { $0.duration > 0 })
    }

    /// Shrinking follows the same single transition.
    @Test func shrinkingUsesOneCoordinatedTransition() {
        var choreography = PillChoreography<String>()
        _ = choreography.show(moment, reduceMotion: false)
        let steps = drain(choreography.show(attention, reduceMotion: false), &choreography)
        #expect(steps.map(\.width) == [120])
        #expect(steps.map(\.content) == ["(!) harbor"])
    }

    /// Pills that arrive during a transition wait; only the newest runs after it.
    @Test func pillsDuringATransitionAreCoalesced() {
        var choreography = PillChoreography<String>()
        _ = choreography.show(normal, reduceMotion: false)
        let first = choreography.show(moment, reduceMotion: false)
        #expect(choreography.show(Motion.Target(content: "dot 3", mode: .normal, width: 60), reduceMotion: false) == nil)
        #expect(choreography.show(attention, reduceMotion: false) == nil)

        let steps = drain(first, &choreography)
        #expect(steps.count == 2)
        #expect(steps.last == Motion.Step(content: "(!) harbor", width: 120, duration: Motion.transitionDuration))
        #expect(!steps.contains { $0.content == "dot 3" })
    }

    @Test func aWidthChangeWithinOneLayoutAnimates() {
        var choreography = PillChoreography<String>()
        _ = choreography.show(normal, reduceMotion: false)
        let step = choreography.show(Motion.Target(content: "dot 3", mode: .normal, width: 68), reduceMotion: false)
        #expect(step == Motion.Step(content: "dot 3", width: 68, duration: Motion.transitionDuration))
        #expect(choreography.stepFinished(reduceMotion: false) == nil)
    }

    @Test func aNewCompletionAnimatesEvenAtTheSameWidth() {
        let first = Motion.Target(content: "Build app", mode: .moment, width: 180, animationID: "one")
        let second = Motion.Target(content: "Ship app", mode: .moment, width: 180, animationID: "two")
        #expect(Motion.steps(from: first, to: second, reduceMotion: false).first?.duration == Motion.transitionDuration)
        #expect(Motion.steps(from: first, to: second, reduceMotion: true).first?.duration == 0)
        let usageUpdate = Motion.Target(content: "Ship app, 92%", mode: .moment, width: 180, animationID: "two")
        #expect(Motion.steps(from: second, to: usageUpdate, reduceMotion: false).first?.duration == 0)
    }

    @Test func reduceMotionChangesLayoutsAtOnce() {
        var choreography = PillChoreography<String>()
        _ = choreography.show(normal, reduceMotion: true)
        let step = choreography.show(moment, reduceMotion: true)
        #expect(step == Motion.Step(content: "harbor needs you", width: 180, duration: 0))
        #expect(choreography.stepFinished(reduceMotion: true) == nil)
    }

    @Test func theSamePillAgainDoesNothing() {
        var choreography = PillChoreography<String>()
        _ = choreography.show(normal, reduceMotion: false)
        #expect(choreography.show(normal, reduceMotion: false) == nil)
    }
}

/// The status item's renderer completion (1.1 §14.6), with a fake clock: pills that arrive during a transition must be shown once
/// it ends, never leave the pill on an interrupted step.
@MainActor
@Suite struct PillStepperTests {
    private typealias Motion = PillMotion<String>

    /// A clock that fires the scheduled steps only when told to.
    @MainActor private final class FakeClock {
        var now: TimeInterval = 0
        private var timers: [(at: TimeInterval, fire: @MainActor () -> Void)] = []

        func schedule(_ seconds: TimeInterval, _ fire: @escaping @MainActor () -> Void) {
            timers.append((now + seconds, fire))
        }

        /// Moves the clock to `time`, firing every timer due by then in order.
        func advance(to time: TimeInterval) {
            while let index = timers.indices.min(by: { timers[$0].at < timers[$1].at }), timers[index].at <= time {
                let timer = timers.remove(at: index)
                now = timer.at
                timer.fire()
            }
            now = time
        }

        var pending: Int { timers.count }
    }

    private final class Drawn {
        var steps: [Motion.Step] = []
    }

    private let normal = Motion.Target(content: "dot 2", mode: .normal, width: 60)
    private let moment = Motion.Target(content: "harbor needs you", mode: .moment, width: 180)
    private let attention = Motion.Target(content: "(!) harbor", mode: .attention, width: 120)
    private let attentionCount3 = Motion.Target(content: "(!) harbor · count 3", mode: .attention, width: 128)

    private func stepper(_ clock: FakeClock, _ drawn: Drawn, reduceMotion: Bool = false) -> PillStepper<String> {
        PillStepper(
            draw: { step, completion in
                drawn.steps.append(step)
                if step.duration > 0 { clock.schedule(step.duration, completion) }
                else { completion() }
            },
            reduceMotion: { reduceMotion }
        )
    }

    /// The reviewer's case: the moment ends and its transition to the rest state starts; a poll then changes the count.
    /// The new pill waits for the transition, then shows with its text.
    @Test func aPillArrivingMidTransitionShowsWhenItEnds() {
        let clock = FakeClock()
        let drawn = Drawn()
        let stepper = stepper(clock, drawn)
        stepper.show(normal)
        stepper.show(moment)
        clock.advance(to: 10)
        #expect(drawn.steps.last == Motion.Step(content: "harbor needs you", width: 180, duration: Motion.transitionDuration))

        stepper.show(attention)
        clock.advance(to: 10.03)
        stepper.show(attentionCount3)
        clock.advance(to: 100)
        #expect(drawn.steps.last == Motion.Step(content: "(!) harbor · count 3", width: 128, duration: Motion.transitionDuration))
        #expect(clock.pending == 0)
    }

    /// Several pills during one transition: only the newest runs after it, and the pill ends with its text shown.
    @Test func pillsDuringATransitionAreCoalesced() {
        let clock = FakeClock()
        let drawn = Drawn()
        let stepper = stepper(clock, drawn)
        stepper.show(normal)
        stepper.show(moment)
        stepper.show(Motion.Target(content: "dot 3", mode: .normal, width: 60))
        stepper.show(attention)
        clock.advance(to: 100)
        #expect(!drawn.steps.contains { $0.content == "dot 3" })
        #expect(drawn.steps.last == Motion.Step(content: "(!) harbor", width: 120, duration: Motion.transitionDuration))
        #expect(clock.pending == 0)
    }

    /// An update cannot start a second transition until the renderer completes the first one.
    @Test func stepsWaitForRendererCompletion() {
        let clock = FakeClock()
        let drawn = Drawn()
        let stepper = stepper(clock, drawn)
        stepper.show(normal)
        stepper.show(moment)
        stepper.show(attention)
        #expect(drawn.steps.map(\.width) == [60, 180])
        clock.advance(to: Motion.transitionDuration - 0.001)
        #expect(drawn.steps.count == 2)
        clock.advance(to: Motion.transitionDuration)
        #expect(drawn.steps.map(\.width) == [60, 180, 120])
        clock.advance(to: 1)
        #expect(clock.pending == 0)
    }

    /// A change within one layout, or any change with Reduce Motion, is drawn at once with no timer.
    @Test func changesWithoutADurationNeedNoTimer() {
        let clock = FakeClock()
        let drawn = Drawn()
        let stepper = stepper(clock, drawn, reduceMotion: true)
        stepper.show(normal)
        stepper.show(moment)
        stepper.show(attention)
        #expect(drawn.steps.map(\.content) == ["dot 2", "harbor needs you", "(!) harbor"])
        #expect(drawn.steps.allSatisfy { $0.duration == 0 })
        #expect(clock.pending == 0)
    }
}

@Suite struct SettingsCopyTests {
    /// "Pill" is the design's word for the menu bar item; nothing else the user sees calls it that (F38).
    @Test func showMomentsSaysMenuBarNotPill() {
        #expect(SettingsCopy.showMomentsDetail == "Briefly show a message in the menu bar when a session finishes or needs you, or a limit passes 90%.")
        #expect(!SettingsCopy.showMomentsDetail.lowercased().contains("pill"))
    }
}
