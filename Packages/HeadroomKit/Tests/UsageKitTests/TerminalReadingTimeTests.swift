import Foundation
import HeadroomModel
import Testing
@testable import UsageKit

/// Claude Code re-runs the status line from cached rate limits, without an API call (at the earliest `resets_at`,
/// at prompt-cache expiry, on UI changes), so the bridge rewrites `statusline-latest.json` with old numbers.
/// A terminal reading is therefore dated by the newest API reply in the payload's `transcript_path`, capped
/// by the file's modification date.
@Suite struct TerminalReadingTimeTests {
    /// When the bridge last rewrote the file.
    private let modified = utc("2026-09-24T15:30:00Z")

    static func assistantLine(_ timestamp: String, model: String = "claude-opus-5-5", sidechain: Bool = false) -> String {
        #"{"type":"assistant","isSidechain":\#(sidechain),"timestamp":"\#(timestamp)","message":{"model":"\#(model)","role":"assistant","usage":{"input_tokens":4,"cache_read_input_tokens":134000,"output_tokens":350}}}"#
    }

    static func userLine(_ timestamp: String, text: String = "thanks") -> String {
        #"{"type":"user","isSidechain":false,"timestamp":"\#(timestamp)","message":{"role":"user","content":"\#(text)"}}"#
    }

    static func systemLine(_ timestamp: String) -> String {
        #"{"type":"system","subtype":"turn_duration","timestamp":"\#(timestamp)","durationMs":1200}"#
    }

    /// Writes `transcript` (one entry per line; nil = no file) and a status line payload pointing at it, whose
    /// `transcript_path` is `transcriptPath` when given. Returns the terminal reading.
    private func read(
        transcript: [String]?, transcriptPath: String? = nil, modified: Date? = nil,
        rateLimits: String = #"{"seven_day":{"used_percentage":85,"resets_at":1790506800}}"#
    ) throws -> PlanUsage? {
        let directory = try makeTempDirectory()
        let transcriptURL = directory.appendingPathComponent("00000000-0000-4000-8000-000000000abc.jsonl")
        if let transcript {
            try Data(transcript.map { $0 + "\n" }.joined().utf8).write(to: transcriptURL)
        }
        let path = try JSONSerialization.data(withJSONObject: transcriptPath ?? transcriptURL.path, options: .fragmentsAllowed)
        let payload = #"{"session_id":"00000000-0000-4000-8000-000000000abc","transcript_path":\#(String(decoding: path, as: UTF8.self)),"rate_limits":\#(rateLimits)}"#
        let url = directory.appendingPathComponent("statusline-latest.json")
        try Data(payload.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified ?? self.modified], ofItemAtPath: url.path)
        return TerminalLimitsReader(fileURL: url).read()
    }

    private func observedAt(transcript: [String]?, transcriptPath: String? = nil) throws -> Date? {
        try read(transcript: transcript, transcriptPath: transcriptPath)?.weekly?.observedAt
    }

    @Test func cachedReRunIsDatedByTheNewestReplyInItsTranscript() throws {
        let transcript = [
            Self.userLine("2026-09-24T09:59:40.000Z"),
            Self.assistantLine("2026-09-24T10:00:00.250Z"),
            Self.systemLine("2026-09-24T10:00:01.000Z"),
            Self.userLine("2026-09-24T15:29:00.000Z", text: "typed, no reply yet"),
        ]
        let usage = try #require(try read(transcript: transcript))
        let weekly = try #require(usage.weekly)
        #expect(weekly.observedAt == utc("2026-09-24T10:00:00Z").addingTimeInterval(0.25))
        #expect(weekly.usedPercent == 85)
        #expect(weekly.resetsAt == utc("2026-09-27T11:00:00Z"))
        #expect(weekly.resetIsEstimated == false)
        #expect(weekly.source == .terminal)
    }

    @Test func bothLimitsShareTheReplyTime() throws {
        let usage = try #require(try read(
            transcript: [Self.assistantLine("2026-09-24T10:00:00Z")],
            rateLimits: #"{"five_hour":{"used_percentage":40,"resets_at":1790263800},"seven_day":{"used_percentage":85,"resets_at":1790506800}}"#
        ))
        #expect(usage.fiveHour?.observedAt == utc("2026-09-24T10:00:00Z"))
        #expect(usage.weekly?.observedAt == utc("2026-09-24T10:00:00Z"))
    }

    @Test func replyWrittenAfterTheFileKeepsTheModificationDate() throws {
        // The reply that brought these numbers can land in the transcript just after the status line ran.
        #expect(try observedAt(transcript: [Self.assistantLine("2026-09-24T15:30:02.000Z")]) == modified)
    }

    @Test func fractionlessTimestampsAreAccepted() throws {
        #expect(try observedAt(transcript: [Self.assistantLine("2026-09-24T10:00:00Z")]) == utc("2026-09-24T10:00:00Z"))
    }

    @Test func syntheticRepliesAreNotAPIReplies() throws {
        let transcript = [
            Self.assistantLine("2026-09-24T10:00:00Z"),
            Self.assistantLine("2026-09-24T12:00:00Z", model: "<synthetic>"),
        ]
        #expect(try observedAt(transcript: transcript) == utc("2026-09-24T10:00:00Z"))
    }

    @Test func subagentRepliesCountAsReplies() throws {
        // A subagent's API reply refreshes the same process's rate limits.
        let transcript = [
            Self.assistantLine("2026-09-24T10:00:00Z"),
            Self.assistantLine("2026-09-24T11:00:00Z", sidechain: true),
        ]
        #expect(try observedAt(transcript: transcript) == utc("2026-09-24T11:00:00Z"))
    }

    @Test func unreadableOrUselessEntriesAreSkipped() throws {
        let transcript = [
            Self.assistantLine("2026-09-24T10:00:00Z"),
            #"{"type":"assistant","timestamp":"yesterday","message":{"model":"claude-opus-5-5"}}"#,
            #"{"type":"assistant","message":{"model":"claude-opus-5-5"}}"#,
            #"{"type":"assistant","timestamp":"2026-09-24T11:00:00Z"}"#,
            #"{"type":"assistant","timestamp":"2026-09-24T11:00:00Z","message":"text"}"#,
            #"{"type":"assistant","timestamp":"2026-09-24T11:00:00Z","message":{"model":"claude-opus-5-5"#,
            "not json, but \"assistant\" is mentioned",
            "",
        ]
        #expect(try observedAt(transcript: transcript) == utc("2026-09-24T10:00:00Z"))
    }

    @Test func withoutAReplyTheModificationDateIsKept() throws {
        #expect(try observedAt(transcript: [Self.userLine("2026-09-24T10:00:00Z")]) == modified)
        #expect(try observedAt(transcript: []) == modified)
    }

    @Test func missingOrUnusableTranscriptKeepsTheModificationDate() throws {
        #expect(try observedAt(transcript: nil) == modified)
        #expect(try observedAt(transcript: nil, transcriptPath: "relative/session.jsonl") == modified)
        #expect(try observedAt(transcript: nil, transcriptPath: "") == modified)
        #expect(try observedAt(transcript: nil, transcriptPath: NSTemporaryDirectory()) == modified)
        // The existing fixture points at a transcript that does not exist here.
        let url = try copyFixture("statusline-latest.json", modified: modified)
        #expect(TerminalLimitsReader(fileURL: url).read()?.weekly?.observedAt == modified)
    }

    @Test func nonStringTranscriptPathKeepsTheLimits() throws {
        let url = try writeTempFile(
            #"{"transcript_path":42,"rate_limits":{"seven_day":{"used_percentage":85,"resets_at":1790506800}}}"#,
            name: "statusline-latest.json", modified: modified
        )
        let weekly = try #require(TerminalLimitsReader(fileURL: url).read()?.weekly)
        #expect(weekly.usedPercent == 85)
        #expect(weekly.observedAt == modified)
    }

    @Test func fifoTranscriptDoesNotBlock() throws {
        let fifo = try makeTempDirectory().appendingPathComponent("session.jsonl")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(try observedAt(transcript: nil, transcriptPath: fifo.path) == modified)
    }

    @Test func replyFarBehindLargeLaterEntriesIsFound() throws {
        // A big tool result after the reply pushes it out of the first tail window.
        let transcript = [
            Self.assistantLine("2026-09-24T10:00:00Z"),
            Self.userLine("2026-09-24T10:00:05Z", text: String(repeating: "x", count: 700 * 1024)),
        ]
        #expect(try observedAt(transcript: transcript) == utc("2026-09-24T10:00:00Z"))
    }

    /// A caller that caches the reading learns which transcript dated it, just before it is read, so it can
    /// notice that transcript changing later. Here the transcript changes at that moment: the reading sees it.
    @Test func reportsTheTranscriptJustBeforeReadingIt() throws {
        let directory = try makeTempDirectory()
        let transcript = directory.appendingPathComponent("session.jsonl")
        try Data((Self.assistantLine("2026-09-24T10:00:00Z") + "\n").utf8).write(to: transcript)
        let url = directory.appendingPathComponent("statusline-latest.json")
        let path = String(decoding: try JSONSerialization.data(withJSONObject: transcript.path, options: .fragmentsAllowed), as: UTF8.self)
        try Data(#"{"transcript_path":\#(path),"rate_limits":{"seven_day":{"used_percentage":85}}}"#.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)

        var reported: [String] = []
        let usage = TerminalLimitsReader(fileURL: url).read { transcriptPath in
            reported.append(transcriptPath)
            try? Data((Self.assistantLine("2026-09-24T11:00:00Z") + "\n").utf8).write(to: transcript)
        }

        #expect(reported == [transcript.path])
        #expect(usage?.weekly?.observedAt == utc("2026-09-24T11:00:00Z"))
    }

    @Test func reportsNoTranscriptWhenNoneIsRead() throws {
        let directory = try makeTempDirectory()
        let url = directory.appendingPathComponent("statusline-latest.json")
        for payload in [#"{"rate_limits":{"seven_day":{"used_percentage":85}}}"#, #"{"transcript_path":"/x/y.jsonl"}"#] {
            try Data(payload.utf8).write(to: url)
            var reported: [String] = []
            _ = TerminalLimitsReader(fileURL: url).read { reported.append($0) }
            #expect(reported.isEmpty, "\(payload)")
        }
    }
}

/// F05 end to end: an idle terminal's cached re-run must not beat a newer desktop sample.
@Suite struct CachedTerminalReRunTests {
    @Test func newerDesktopSampleBeatsACachedReRunAndBorrowsItsExactReset() throws {
        let directory = try makeTempDirectory()
        let transcript = directory.appendingPathComponent("session.jsonl")
        try Data((TerminalReadingTimeTests.assistantLine("2026-09-24T10:00:00Z") + "\n").utf8).write(to: transcript)
        // The five-hour window (40 % until 15:30) expired, so the 15:30 re-run carries only the cached weekly 85 %.
        let payload = #"{"transcript_path":"\#(transcript.path)","rate_limits":{"seven_day":{"used_percentage":85,"resets_at":1790506800}}}"#
        let url = directory.appendingPathComponent("statusline-latest.json")
        try Data(payload.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: utc("2026-09-24T15:30:00Z")], ofItemAtPath: url.path)

        let samples = [
            sample("2026-09-24T09:45:00Z", fh: 30, sd: 84),
            sample("2026-09-24T15:21:21Z", fh: 71, sd: 100),
            sample("2026-09-24T15:27:02Z", fh: 71, sd: 100),
        ]
        let now = utc("2026-09-24T15:31:00Z")
        let result = PlanUsageResolver.resolve(
            desktop: DesktopUsageAnalyzer.currentUsage(samples: samples, now: now), desktopSamples: samples,
            terminal: TerminalLimitsReader(fileURL: url).read(), now: now
        )
        let weekly = try #require(result.weekly)
        #expect(weekly.usedPercent == 100)
        #expect(weekly.source == .desktopApp)
        #expect(weekly.observedAt == utc("2026-09-24T15:27:02Z"))
        // Still the terminal's exact reset: the desktop history shows no reset since 10:00.
        #expect(weekly.resetsAt == utc("2026-09-27T11:00:00Z"))
        #expect(weekly.resetIsEstimated == false)
    }
}

/// The transcript tail windows (last 64 KB, ×4 up to 8 MB).
@Suite struct TranscriptReplyTimeTests {
    private let reply = TerminalReadingTimeTests.assistantLine("2026-09-24T10:00:00Z")
    private let filler = TerminalReadingTimeTests.userLine("2026-09-24T10:00:05Z", text: String(repeating: "x", count: 200))

    private func write(_ lines: [String]) throws -> (path: String, size: Int) {
        let data = Data(lines.map { $0 + "\n" }.joined().utf8)
        let url = try makeTempDirectory().appendingPathComponent("session.jsonl")
        try data.write(to: url)
        return (url.path, data.count)
    }

    @Test func aReplyStartingExactlyAtTheLargestWindowIsFound() throws {
        let file = try write([filler, reply, filler, filler])
        let tail = file.size - filler.utf8.count - 1
        #expect(TranscriptReplyTime.newestReply(inTranscriptAt: file.path, initialWindow: 16, maxWindow: tail)
            == utc("2026-09-24T10:00:00Z"))
    }

    @Test func aReplyCutByTheLargestWindowIsNotParsed() throws {
        let file = try write([filler, reply, filler, filler])
        let tail = file.size - filler.utf8.count - 1
        #expect(TranscriptReplyTime.newestReply(inTranscriptAt: file.path, initialWindow: 16, maxWindow: tail - 1) == nil)
    }

    @Test func windowsGrowUntilAReplyIsFound() throws {
        let file = try write([reply] + Array(repeating: filler, count: 50))
        #expect(TranscriptReplyTime.newestReply(inTranscriptAt: file.path, initialWindow: 64, maxWindow: 1 << 20)
            == utc("2026-09-24T10:00:00Z"))
    }

    @Test func theNewestOfSeveralRepliesWins() throws {
        let later = TerminalReadingTimeTests.assistantLine("2026-09-24T10:30:00Z")
        let file = try write([reply, filler, later, filler])
        #expect(TranscriptReplyTime.newestReply(inTranscriptAt: file.path) == utc("2026-09-24T10:30:00Z"))
    }

    @Test func aFileWithoutAFinalNewlineIsRead() throws {
        let url = try makeTempDirectory().appendingPathComponent("session.jsonl")
        try Data((filler + "\n" + reply).utf8).write(to: url)
        #expect(TranscriptReplyTime.newestReply(inTranscriptAt: url.path, initialWindow: 16, maxWindow: 4096)
            == utc("2026-09-24T10:00:00Z"))
    }

    @Test func emptyFileAndPathsWithNULHaveNoReply() throws {
        let file = try write([])
        #expect(TranscriptReplyTime.newestReply(inTranscriptAt: file.path) == nil)
        let real = try write([reply])
        #expect(TranscriptReplyTime.newestReply(inTranscriptAt: real.path + "\0ignored") == nil)
    }
}
