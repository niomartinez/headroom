import Foundation
import Testing
@testable import UsageKit

@Suite struct DesktopUsageReaderTests {
    private let orgA = "11111111-aaaa-4aaa-8aaa-000000000001"
    private let orgB = "22222222-bbbb-4bbb-8bbb-000000000002"

    @Test func versionTwoFixtureParsesSortedWithMillisecondTimes() throws {
        let samples = try DesktopUsageReader(fileURL: try copyFixture("plan-usage-history-v2.json")).readSamples()

        #expect(samples.map(\.time) == [
            utc("2026-09-24T10:00:00Z"), utc("2026-09-24T11:00:00Z"),
            utc("2026-09-24T12:00:00Z"), utc("2026-09-24T13:00:00Z"),
        ])
        #expect(samples.map(\.org) == [orgB, orgA, orgA, orgA])
        #expect(samples[0] == DesktopUsageSample(time: utc("2026-09-24T10:00:00Z"), org: orgB, fiveHour: 3.25, weekly: 7, extra: 12))
        #expect(samples[1] == DesktopUsageSample(time: utc("2026-09-24T11:00:00Z"), org: orgA, fiveHour: 8, weekly: 39, extra: 0))
        #expect(samples[2] == DesktopUsageSample(time: utc("2026-09-24T12:00:00Z"), org: orgA, fiveHour: 12, weekly: 40.5, extra: nil))
        #expect(samples[3] == DesktopUsageSample(time: utc("2026-09-24T13:00:00Z"), org: orgA, fiveHour: 14, weekly: nil, extra: nil))
    }

    @Test func numericVersionTwoIsAccepted() throws {
        // The desktop app writes `"version":2` (a number) today; the spec shows a string.
        let url = try writeTempFile(#"{"version":2,"samples":[{"t":1790244000123,"org":"o","u":{"fh":1,"sd":2,"xu":null}}]}"#)
        let samples = try DesktopUsageReader(fileURL: url).readSamples()
        #expect(samples == [DesktopUsageSample(time: Date(timeIntervalSince1970: 1_790_244_000.123), org: "o", fiveHour: 1, weekly: 2, extra: nil)])
    }

    @Test func zeroSamplesParseAsEmpty() throws {
        let url = try writeTempFile(#"{"version":"2","samples":[]}"#)
        #expect(try DesktopUsageReader(fileURL: url).readSamples().isEmpty)
    }

    @Test func missingFileThrowsFileMissing() throws {
        let url = try makeTempDirectory().appendingPathComponent("plan-usage-history.json")
        #expect(throws: DesktopUsageError.fileMissing) { try DesktopUsageReader(fileURL: url).readSamples() }
    }

    @Test func directoryInsteadOfFileThrowsFileMissing() throws {
        let url = try makeTempDirectory()
        #expect(throws: DesktopUsageError.fileMissing) { try DesktopUsageReader(fileURL: url).readSamples() }
    }

    @Test(arguments: [
        #"{"version":"3","samples":[]}"#,
        #"{"version":3,"samples":[]}"#,
        #"{"version":2.5,"samples":[]}"#,
        #"{"version":null,"samples":[]}"#,
        #"{"samples":[]}"#,
        #"{"version":"2"}"#,
        #"{"version":"2","samples":{"t":1}}"#,
        #"{"version":"2","samples":[1,2]}"#,
        #"{"version":"2","samples":[{"t":"yesterday","org":"o","u":{"fh":1,"sd":1}}]}"#,
        #"{"version":"2","samples":[{"t":1790244000000,"u":{"fh":1,"sd":1}}]}"#,
        #"{"version":"2","samples":[{"t":1790244000000,"org":"o"}]}"#,
        #"{"version":"2","samples":[{"t":1790244000000,"org":"o","u":{"fh":"8","sd":1}}]}"#,
        #"{"version":"2","samples":[{"t":1790244000000,"org":"o","u":[]}]}"#,
        #"[{"t":1790244000000,"org":"o","u":{"fh":1,"sd":1}}]"#,
        #"{"version":"2","samples":[{"t":1790244000000,"org":"o","u":{"fh":1,"sd":1}}"#,
        "",
        "not json",
    ])
    func unknownVersionOrShapeIsUnrecognized(json: String) throws {
        let url = try writeTempFile(json)
        #expect(throws: DesktopUsageError.unrecognizedFormat) { try DesktopUsageReader(fileURL: url).readSamples() }
    }

    @Test func fifoIsTreatedAsMissingWithoutBlocking() throws {
        let url = try makeTempDirectory().appendingPathComponent("plan-usage-history.json")
        #expect(mkfifo(url.path, 0o600) == 0)
        #expect(throws: DesktopUsageError.fileMissing) { try DesktopUsageReader(fileURL: url).readSamples() }
    }

    @Test func symlinkToTheFileIsFollowed() throws {
        let target = try copyFixture("plan-usage-history-v2.json")
        let link = try makeTempDirectory().appendingPathComponent("plan-usage-history.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(try DesktopUsageReader(fileURL: link).readSamples().count == 4)
    }

    @Test func oversizedFileIsUnrecognized() throws {
        let url = try writeTempFile(Data(repeating: 0x20, count: DesktopUsageReader.maxFileSize + 1))
        #expect(throws: DesktopUsageError.unrecognizedFormat) { try DesktopUsageReader(fileURL: url).readSamples() }
    }

    @Test func equalTimesKeepFileOrder() throws {
        let url = try writeTempFile(#"""
        {"version":"2","samples":[
        {"t":1790244000000,"org":"first","u":{"fh":1,"sd":1}},
        {"t":1790244000000,"org":"second","u":{"fh":2,"sd":2}}]}
        """#)
        #expect(try DesktopUsageReader(fileURL: url).readSamples().map(\.org) == ["first", "second"])
    }
}
