import Foundation
import Testing
@testable import HeadroomUI

@Suite struct HeadroomFormatTests {
    let format = Fixture.format
    let now = Fixture.now

    // MARK: Weekly reset (§1.2)

    @Test func weeklyExactOnTheHour() {
        let sunday7pm = Fixture.date(2026, 9, 27, 19, 0)
        #expect(format.weeklyReset(at: sunday7pm, estimated: false) == "resets Sun 7 PM")
    }

    @Test func weeklyEstimatedHasTilde() {
        let sunday7pm = Fixture.date(2026, 9, 27, 19, 0)
        #expect(format.weeklyReset(at: sunday7pm, estimated: true) == "resets ~Sun 7 PM")
    }

    @Test func weeklyShowsMinutesWhenNotOnTheHour() {
        let monday = Fixture.date(2026, 9, 28, 9, 30)
        #expect(format.weeklyReset(at: monday, estimated: false) == "resets Mon 9:30 AM")
    }

    @Test func weeklyUsesTheInjectedTimeZone() {
        // 11:00 UTC is 19:00 in Manila but 07:00 in New York.
        let reset = Fixture.date(2026, 9, 27, 19, 0)
        let newYork = HeadroomFormat(calendar: Fixture.calendar, timeZone: TimeZone(identifier: "America/New_York")!, locale: Fixture.posix)
        #expect(newYork.weeklyReset(at: reset, estimated: false) == "resets Sun 7 AM")
    }

    @Test func weeklyTwentyFourHourLocaleAlwaysShowsMinutes() {
        let british = HeadroomFormat(calendar: Fixture.calendar, timeZone: Fixture.manila, locale: Locale(identifier: "en_GB"))
        #expect(british.weeklyReset(at: Fixture.date(2026, 9, 27, 19, 0), estimated: false) == "resets Sun 19:00")
    }

    @Test func weeklyUnknownReset() {
        // Spec §3.2 wording.
        #expect(HeadroomFormat.unknownReset == "reset unknown")
        #expect(format.weeklyReset(at: nil, estimated: true) == "reset unknown")
    }

    // MARK: 5-hour reset (§1.2)

    @Test func fiveHourCountdown() {
        let reset = now.addingTimeInterval(2 * 3600 + 50 * 60)
        #expect(format.fiveHourReset(at: reset, estimated: false, now: now) == "resets in 2h 50m")
        #expect(format.fiveHourReset(at: reset, estimated: true, now: now) == "resets ~in 2h 50m")
    }

    @Test func fiveHourRoundsPartialMinutesUp() {
        let reset = now.addingTimeInterval(2 * 3600 + 49 * 60 + 30)
        #expect(format.fiveHourReset(at: reset, estimated: false, now: now) == "resets in 2h 50m")
        #expect(format.fiveHourReset(at: now.addingTimeInterval(20), estimated: false, now: now) == "resets in 1m")
    }

    @Test func fiveHourWholeHoursAndMinutesOnly() {
        #expect(format.fiveHourReset(at: now.addingTimeInterval(3 * 3600), estimated: false, now: now) == "resets in 3h")
        #expect(format.fiveHourReset(at: now.addingTimeInterval(45 * 60), estimated: false, now: now) == "resets in 45m")
    }

    @Test func fiveHourNotStarted() {
        #expect(format.fiveHourReset(at: nil, estimated: false, now: now) == "not started")
        #expect(format.fiveHourReset(at: now, estimated: false, now: now) == "not started")
        #expect(format.fiveHourReset(at: now.addingTimeInterval(-60), estimated: true, now: now) == "not started")
    }

    @Test func fiveHourHugeIntervalDoesNotTrap() {
        let farFuture = Date(timeIntervalSinceReferenceDate: 1e15)
        #expect(format.fiveHourReset(at: farFuture, estimated: false, now: now).hasPrefix("resets in "))
    }

    // MARK: Age

    @Test func ageBuckets() {
        #expect(format.age(of: now, now: now) == "just now")
        #expect(format.age(of: now.addingTimeInterval(-59), now: now) == "just now")
        #expect(format.age(of: now.addingTimeInterval(-120), now: now) == "2m ago")
        #expect(format.age(of: now.addingTimeInterval(-(59 * 60 + 59)), now: now) == "59m ago")
        #expect(format.age(of: now.addingTimeInterval(-3 * 3600 - 600), now: now) == "3h ago")
        #expect(format.age(of: now.addingTimeInterval(-2 * 86_400 - 5), now: now) == "2d ago")
    }

    @Test func ageInTheFutureIsJustNow() {
        #expect(format.age(of: now.addingTimeInterval(300), now: now) == "just now")
    }

    // MARK: Spoken (VoiceOver)

    @Test func spokenResetsUseWordsForTheMarks() {
        let sunday7pm = Fixture.date(2026, 9, 27, 19, 0)
        #expect(format.spokenWeeklyReset(at: sunday7pm, estimated: false) == "resets Sunday 7 PM")
        #expect(format.spokenWeeklyReset(at: sunday7pm, estimated: true) == "resets about Sunday 7 PM")
        #expect(format.spokenWeeklyReset(at: nil, estimated: true) == "reset unknown")
        #expect(format.spokenFiveHourReset(at: now.addingTimeInterval(3600), estimated: true, now: now) == "resets in about 1 hour")
        #expect(format.spokenFiveHourReset(at: nil, estimated: false, now: now) == "not started")
    }

    @Test func spokenCountdownSpellsUnits() {
        #expect(format.spokenCountdown(2 * 3600 + 50 * 60) == "2 hours 50 minutes")
        #expect(format.spokenCountdown(3 * 3600) == "3 hours")
        #expect(format.spokenCountdown(3600 + 60) == "1 hour 1 minute")
        #expect(format.spokenCountdown(20) == "1 minute")
        #expect(format.spokenCountdown(0) == "0 minutes")
    }

    @Test func spokenAgeSpellsUnits() {
        #expect(format.spokenAge(of: now.addingTimeInterval(-30), now: now) == "just now")
        #expect(format.spokenAge(of: now.addingTimeInterval(-60), now: now) == "1 minute ago")
        #expect(format.spokenAge(of: now.addingTimeInterval(-42 * 60), now: now) == "42 minutes ago")
        #expect(format.spokenAge(of: now.addingTimeInterval(-3600), now: now) == "1 hour ago")
        #expect(format.spokenAge(of: now.addingTimeInterval(-3 * 86_400), now: now) == "3 days ago")
    }

    // MARK: Tokens

    @Test func tokensAsInTheSpec() {
        #expect(format.tokens(used: 724_000, window: 1_000_000) == "724k of 1M tokens")
        #expect(format.tokens(used: 52_400, window: 200_000) == "52k of 200k tokens")
    }

    @Test func tokenCounts() {
        #expect(format.tokenCount(0) == "0")
        #expect(format.tokenCount(-5) == "0")
        #expect(format.tokenCount(850) == "850")
        #expect(format.tokenCount(1_499) == "1k")
        #expect(format.tokenCount(999_400) == "999k")
        #expect(format.tokenCount(999_600) == "1M")
        #expect(format.tokenCount(1_500_000) == "1.5M")
        #expect(format.tokenCount(2_000_000) == "2M")
        #expect(format.tokenCount(Int.max).hasSuffix("M"))
    }

    // MARK: Percent

    @Test func percentsRoundToIntegers() {
        #expect(format.percent(89) == "89%")
        #expect(format.percent(88.5) == "89%")
        #expect(format.percent(14.4) == "14%")
        #expect(format.percent(0) == "0%")
    }

    @Test func percentsClampAndRejectGarbage() {
        #expect(format.percent(150) == "100%")
        #expect(format.percent(-3) == "0%")
        #expect(format.percent(.nan) == "–")
        #expect(format.percent(.infinity) == "–")
        #expect(HeadroomFormat.roundedPercent(.nan) == nil)
        #expect(HeadroomFormat.roundedPercent(99.6) == 100)
    }
}
