import Foundation
import Testing

@Suite struct PeriodicCheckTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func theFirstReadLooksUp() {
        var check = PeriodicCheck(interval: 60)
        var lookups = 0
        let value = check.value(at: t0) { lookups += 1; return true }
        #expect(value)
        #expect(lookups == 1)
    }

    @Test func readsInsideTheIntervalReuseTheLastAnswer() {
        var check = PeriodicCheck(interval: 60)
        var lookups = 0
        _ = check.value(at: t0) { lookups += 1; return true }
        let later = check.value(at: t0.addingTimeInterval(59)) { lookups += 1; return false }
        #expect(later)
        #expect(lookups == 1)
    }

    @Test func aReadAfterTheIntervalLooksUpAgain() {
        var check = PeriodicCheck(interval: 60)
        _ = check.value(at: t0) { true }
        var lookups = 0
        let later = check.value(at: t0.addingTimeInterval(60)) { lookups += 1; return false }
        #expect(!later)
        #expect(lookups == 1)
    }

    @Test func invalidatingForcesTheNextReadToLookUp() {
        var check = PeriodicCheck(interval: 60)
        _ = check.value(at: t0) { false }
        check.invalidate()
        let value = check.value(at: t0.addingTimeInterval(1)) { true }
        #expect(value)
    }

    /// The clock can step back (set by hand, or corrected after sleep); that must not freeze the answer.
    @Test func aClockSetBackLooksUpAgain() {
        var check = PeriodicCheck(interval: 60)
        _ = check.value(at: t0) { false }
        let value = check.value(at: t0.addingTimeInterval(-3600)) { true }
        #expect(value)
    }

    // The poll looks the app up on its worker, off the main thread: it asks whether a lookup is
    // due, and hands the fresh answer back.

    @Test func nothingIsCurrentBeforeTheFirstLookup() {
        let check = PeriodicCheck(interval: 60)
        #expect(check.current(at: t0) == nil)
    }

    @Test func aRecordedAnswerIsCurrentForTheInterval() {
        var check = PeriodicCheck(interval: 60)
        check.record(true, at: t0)
        #expect(check.current(at: t0.addingTimeInterval(59)) == true)
        #expect(check.current(at: t0.addingTimeInterval(60)) == nil)
        #expect(check.current(at: t0.addingTimeInterval(-1)) == nil)
    }

    @Test func invalidatingMakesALookupDue() {
        var check = PeriodicCheck(interval: 60)
        check.record(false, at: t0)
        check.invalidate()
        #expect(check.current(at: t0.addingTimeInterval(1)) == nil)
    }

    @Test func aRecordedAnswerIsWhatTheNextReadReturns() {
        var check = PeriodicCheck(interval: 60)
        check.record(true, at: t0)
        var lookups = 0
        let value = check.value(at: t0.addingTimeInterval(10)) { lookups += 1; return false }
        #expect(value)
        #expect(lookups == 0)
    }

    @Test func theDesktopAppIsLookedUpByItsVerifiedBundleIdentifier() {
        #expect(ClaudeDesktopApp.bundleIdentifier == "com.anthropic.claudefordesktop")
        #expect(ClaudeDesktopApp.recheckInterval >= 30)
    }
}
