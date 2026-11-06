import Foundation
import HeadroomModel
import Testing
@testable import UsageKit

@Suite struct TerminalLimitsReaderTests {
    private let modified = utc("2026-09-24T13:05:00Z")

    private func read(_ json: String) throws -> PlanUsage? {
        TerminalLimitsReader(fileURL: try writeTempFile(json, name: "statusline-latest.json", modified: modified)).read()
    }

    @Test func rateLimitsBecomeExactReadingsObservedAtModificationDate() throws {
        let url = try copyFixture("statusline-latest.json", modified: modified)
        let usage = try #require(TerminalLimitsReader(fileURL: url).read())

        #expect(usage.fiveHour == LimitReading(
            kind: .fiveHour, usedPercent: 20, resetsAt: utc("2026-09-24T15:30:00Z"),
            resetIsEstimated: false, observedAt: modified, source: .terminal
        ))
        #expect(usage.weekly == LimitReading(
            kind: .weekly, usedPercent: 90.5, resetsAt: utc("2026-09-27T11:00:00Z"),
            resetIsEstimated: false, observedAt: modified, source: .terminal
        ))
        #expect(usage.extraUsagePercent == nil)
    }

    @Test func missingRateLimitsGiveNil() throws {
        #expect(try read(#"{"session_id":"x","context_window":{"used_percentage":3}}"#) == nil)
        #expect(try read(#"{"rate_limits":null}"#) == nil)
        #expect(try read(#"{"rate_limits":{}}"#) == nil)
        #expect(try read(#"{"rate_limits":"soon"}"#) == nil)
    }

    @Test func missingFileGivesNil() throws {
        let url = try makeTempDirectory().appendingPathComponent("statusline-latest.json")
        #expect(TerminalLimitsReader(fileURL: url).read() == nil)
    }

    @Test(arguments: ["", "{", "not json", "[1,2,3]", "42", #"{"rate_limits":{"five_hour":{"used_percentage":20"#])
    func malformedJSONGivesNil(json: String) throws {
        #expect(try read(json) == nil)
    }

    @Test func repeatedReadsSeeTheNewModificationDate() throws {
        // The app keeps one reader and polls it; a cached mtime would freeze observedAt.
        let url = try copyFixture("statusline-latest.json", modified: modified)
        let reader = TerminalLimitsReader(fileURL: url)
        #expect(reader.read()?.fiveHour?.observedAt == modified)

        let later = modified.addingTimeInterval(120)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: url.path)
        #expect(reader.read()?.fiveHour?.observedAt == later)
    }

    @Test func fifoGivesNilWithoutBlocking() throws {
        let url = try makeTempDirectory().appendingPathComponent("statusline-latest.json")
        #expect(mkfifo(url.path, 0o600) == 0)
        #expect(TerminalLimitsReader(fileURL: url).read() == nil)
    }

    @Test func oversizedFileGivesNil() throws {
        let url = try writeTempFile(Data(repeating: 0x20, count: TerminalLimitsReader.maxFileSize + 1))
        #expect(TerminalLimitsReader(fileURL: url).read() == nil)
    }

    @Test func onlyFiveHourPresent() throws {
        let usage = try #require(try read(#"{"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":1790263800}}}"#))
        #expect(usage.fiveHour?.usedPercent == 20)
        #expect(usage.weekly == nil)
    }

    @Test func onlySevenDayPresent() throws {
        let usage = try #require(try read(#"{"rate_limits":{"seven_day":{"used_percentage":90,"resets_at":1790506800}}}"#))
        #expect(usage.fiveHour == nil)
        #expect(usage.weekly?.usedPercent == 90)
        #expect(usage.weekly?.resetsAt == utc("2026-09-27T11:00:00Z"))
    }

    @Test func malformedLimitIsSkippedAndTheOtherKept() throws {
        let usage = try #require(try read(#"""
        {"rate_limits":{"five_hour":{"used_percentage":"lots","resets_at":1790263800},
                        "seven_day":{"used_percentage":90,"resets_at":1790506800}}}
        """#))
        #expect(usage.fiveHour == nil)
        #expect(usage.weekly?.usedPercent == 90)

        let other = try #require(try read(#"{"rate_limits":{"five_hour":true,"seven_day":{"used_percentage":5}}}"#))
        #expect(other.fiveHour == nil)
        #expect(other.weekly?.usedPercent == 5)
    }

    @Test func missingResetTimeKeepsUsageWithUnknownReset() throws {
        let usage = try #require(try read(#"{"rate_limits":{"five_hour":{"used_percentage":12.5,"resets_at":"later"}}}"#))
        #expect(usage.fiveHour?.usedPercent == 12.5)
        #expect(usage.fiveHour?.resetsAt == nil)
        #expect(usage.fiveHour?.resetIsEstimated == false)
    }

    @Test func fractionalResetSecondsAreKept() throws {
        let usage = try #require(try read(#"{"rate_limits":{"five_hour":{"used_percentage":1,"resets_at":1790263800.5}}}"#))
        #expect(usage.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_790_263_800.5))
    }

    // MARK: resets_at sanity (spec §2.4: epoch seconds)

    private func fiveHour(resetsAt: String) throws -> LimitReading {
        try #require(try read(#"{"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":\#(resetsAt)}}}"#)?.fiveHour)
    }

    @Test func millisecondResetTimesAreConverted() throws {
        #expect(try fiveHour(resetsAt: "1790263800000").resetsAt == utc("2026-09-24T15:30:00Z"))
        #expect(try fiveHour(resetsAt: "1790263800500").resetsAt == Date(timeIntervalSince1970: 1_790_263_800.5))
        let weekly = try #require(try read(#"{"rate_limits":{"seven_day":{"used_percentage":90,"resets_at":1790506800000}}}"#)?.weekly)
        #expect(weekly.resetsAt == utc("2026-09-27T11:00:00Z"))
    }

    /// Before 2020, more than 400 days after the reading, or not a time at all: the usage is kept,
    /// the reset is unknown.
    @Test(arguments: [
        "0", "-1790263800", "1", "1000000", "1577836799", // 2019-12-31T23:59:59Z
        "1824901500", // observedAt + 401 days
        "99999999999", // below the milliseconds cut-off, but year 5138 as seconds
        "1577836799000", // milliseconds, 2019-12-31T23:59:59Z
        "1e300", "1e20",
    ])
    func implausibleResetTimesAreIgnored(resetsAt: String) throws {
        let reading = try fiveHour(resetsAt: resetsAt)
        #expect(reading.resetsAt == nil)
        #expect(reading.usedPercent == 20)
        #expect(reading.resetIsEstimated == false)
    }

    @Test func plausibleBoundariesAreKept() throws {
        #expect(try fiveHour(resetsAt: "1577836800").resetsAt == utc("2020-01-01T00:00:00Z"))
        // A reset already past at observedAt is kept: the resolver rolls it over (spec §3.1).
        #expect(try fiveHour(resetsAt: "1790200000").resetsAt == Date(timeIntervalSince1970: 1_790_200_000))
        let limit = modified.addingTimeInterval(400 * 86_400)
        #expect(try fiveHour(resetsAt: "\(Int(limit.timeIntervalSince1970))").resetsAt == limit)
    }

    @Test func payloadCanBeParsedWithoutAFile() throws {
        let data = Data(#"{"rate_limits":{"seven_day":{"used_percentage":90,"resets_at":1790506800}}}"#.utf8)
        let usage = try #require(TerminalLimitsReader.limits(fromStatusLinePayload: data, observedAt: modified))
        #expect(usage.weekly?.observedAt == modified)
        #expect(usage.weekly?.source == .terminal)
    }
}
