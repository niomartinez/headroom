import HeadroomModel
import Testing

@Suite struct MomentQueueTests {
    private let finishedA = Moment.sessionFinished(sessionID: "a", name: "Alpha")
    private let finishedB = Moment.sessionFinished(sessionID: "b", name: "Beta")
    private let needsC = Moment.sessionNeedsInput(sessionID: "c", name: "Gamma")
    private let weekly90 = Moment.limitCrossed(kind: .weekly, percent: 90)

    @Test func enqueueIntoEmptyQueueStartsTheFirstMoment() {
        var queue = MomentQueue()
        let started = queue.enqueue([finishedA, finishedB])
        #expect(started == finishedA)
        #expect(queue.current == finishedA)
        #expect(queue.pending == [finishedB])
    }

    @Test func enqueueWhileShowingOnlyQueues() {
        var queue = MomentQueue()
        _ = queue.enqueue([finishedA])
        let started = queue.enqueue([needsC])
        #expect(started == nil)
        #expect(queue.current == finishedA)
        #expect(queue.pending == [needsC])
    }

    @Test func advanceShowsMomentsOneAtATimeInOrder() {
        var queue = MomentQueue()
        _ = queue.enqueue([finishedA, needsC, weekly90])
        #expect(queue.advance() == needsC)
        #expect(queue.advance() == weekly90)
        #expect(queue.advance() == nil)
        #expect(queue.current == nil)
        #expect(queue.pending.isEmpty)
    }

    @Test func enqueueNothingStartsNothing() {
        var queue = MomentQueue()
        #expect(queue.enqueue([]) == nil)
        #expect(queue.current == nil)
    }

    @Test func duplicatesOfShowingOrQueuedMomentsAreSkipped() {
        var queue = MomentQueue()
        _ = queue.enqueue([finishedA, needsC, needsC])
        _ = queue.enqueue([finishedA, needsC])
        #expect(queue.current == finishedA)
        #expect(queue.pending == [needsC])
    }

    @Test func burstIsTrimmedToCapacityDroppingTheOldest() {
        var queue = MomentQueue()
        let burst = (0..<(MomentQueue.capacity + 4)).map {
            Moment.sessionFinished(sessionID: "s\($0)", name: "Session \($0)")
        }
        _ = queue.enqueue(burst)
        #expect(queue.current == burst[0])
        #expect(queue.pending.count == MomentQueue.capacity)
        #expect(queue.pending.last == burst.last)
        #expect(queue.pending.first == burst[burst.count - MomentQueue.capacity])
    }

    @Test func removeAllClearsCurrentAndPending() {
        var queue = MomentQueue()
        _ = queue.enqueue([finishedA, finishedB])
        queue.removeAll()
        #expect(queue.current == nil)
        #expect(queue.pending.isEmpty)
        #expect(queue.enqueue([needsC]) == needsC)
    }

    /// Opening the panel (or Dismiss) drops "needs you" moments for the sessions just seen (1.1 §14.4).
    @Test func removeAllWhereDropsMatchingQueuedMoments() {
        var queue = MomentQueue()
        _ = queue.enqueue([finishedA, needsC, finishedB])
        let droppedShowing = queue.removeAll { $0.needsInputSessionID == "c" }
        #expect(!droppedShowing)
        #expect(queue.current == finishedA)
        #expect(queue.pending == [finishedB])
    }

    @Test func removeAllWhereEndsTheShowingMomentAndAdvances() {
        var queue = MomentQueue()
        _ = queue.enqueue([needsC, finishedA])
        let droppedShowing = queue.removeAll { $0.needsInputSessionID == "c" }
        #expect(droppedShowing)
        #expect(queue.current == finishedA)
        #expect(queue.pending.isEmpty)
    }

    @Test func removeAllWhereCanEmptyTheQueue() {
        var queue = MomentQueue()
        _ = queue.enqueue([needsC])
        let droppedShowing = queue.removeAll { $0.needsInputSessionID != nil }
        #expect(droppedShowing)
        #expect(queue.current == nil)
        #expect(queue.enqueue([finishedB]) == finishedB)
    }

    @Test func onlyNeedsYouMomentsNameASessionToDrop() {
        #expect(needsC.needsInputSessionID == "c")
        #expect(finishedA.needsInputSessionID == nil)
        #expect(weekly90.needsInputSessionID == nil)
    }

    @Test func eachMomentShowsForFourSeconds() {
        #expect(MomentQueue.displayDuration == .seconds(4))
    }
}
