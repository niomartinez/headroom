import Foundation
import Testing

@Suite struct PollOrderingTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func pollsFinishingInOrderAreAllApplied() {
        var ordering = PollOrdering()
        let first = ordering.begin(at: t0)
        let appliedFirst = ordering.shouldApply(first)
        let second = ordering.begin(at: t0.addingTimeInterval(2))
        let appliedSecond = ordering.shouldApply(second)
        #expect(appliedFirst)
        #expect(appliedSecond)
    }

    @Test func anOlderPollFinishingAfterANewerOneIsDropped() {
        var ordering = PollOrdering()
        let older = ordering.begin(at: t0)
        let newer = ordering.begin(at: t0.addingTimeInterval(0.5))
        let appliedNewer = ordering.shouldApply(newer)
        let appliedOlder = ordering.shouldApply(older)
        #expect(appliedNewer)
        #expect(!appliedOlder)
    }

    @Test func aPollIsAppliedAtMostOnce() {
        var ordering = PollOrdering()
        let poll = ordering.begin(at: t0)
        let firstTime = ordering.shouldApply(poll)
        let secondTime = ordering.shouldApply(poll)
        #expect(firstTime)
        #expect(!secondTime)
    }

    /// The system clock can step back (set by hand, or corrected after sleep). Polls started
    /// afterwards must still be applied, or the pill and panel freeze until the clock catches up.
    @Test func pollsAfterTheClockIsSetBackAreStillApplied() {
        var ordering = PollOrdering()
        let beforeStep = ordering.begin(at: t0)
        let appliedBeforeStep = ordering.shouldApply(beforeStep)
        let afterStep = ordering.begin(at: t0.addingTimeInterval(-3600))
        let appliedAfterStep = ordering.shouldApply(afterStep)
        let next = ordering.begin(at: t0.addingTimeInterval(-3598))
        let appliedNext = ordering.shouldApply(next)
        #expect(appliedBeforeStep)
        #expect(appliedAfterStep)
        #expect(appliedNext)
    }

    @Test func thePollKeepsItsStartTimeForTheSnapshot() {
        var ordering = PollOrdering()
        let poll = ordering.begin(at: t0)
        #expect(poll.startedAt == t0)
    }
}
