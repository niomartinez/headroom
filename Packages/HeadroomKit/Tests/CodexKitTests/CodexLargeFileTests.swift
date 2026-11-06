import Foundation
import HeadroomModel
import Testing
@testable import CodexKit

/// Files generated at test time, never committed (1.1 §11.1): a 5 MB line, a 20 MB rollout, and the poll budget
/// over 600 rollouts.
@Suite("Codex large files and the poll budget", .serialized)
struct CodexLargeFileTests {
    /// A response line of about `bytes` bytes that matches no needle.
    private func filler(at: String, bytes: Int) -> String {
        RolloutText.message(at: at, text: String(repeating: "f", count: max(0, bytes - 150)))
    }

    private func appendHistory(_ megabytes: Int, to url: URL) throws {
        let block = Data(String(repeating: filler(at: "2026-09-23T13:32:00Z", bytes: 64 * 1_024), count: 16).utf8)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        for _ in 0..<megabytes { try handle.write(contentsOf: block) }
    }

    @Test(arguments: [false, true])
    func coldStartRecoversLifecycleBeforeTheEightMegabyteTail(completed: Bool) throws {
        let home = try CodexHome()
        let file = try home.install("open_turn")
        try home.lock([CodexFixtures.threadID("open_turn")])
        if completed { try home.append(RolloutText.complete(at: "2026-09-23T13:31:00Z", turn: "t1"), to: file) }
        try appendHistory(17, to: file)
        try home.append(RolloutText.tokenCount(at: "2026-09-23T13:33:00Z", rateLimits: RolloutText.weekly(64)), to: file)
        let reader = home.reader()
        let reading = reader.read(now: testNow)
        #expect(reading.sessions.first?.activity == (completed ? .idle : .working))
        #expect(reading.usage.limits.first?.usedPercent == 64)
        #expect(reader.tailBytesRead <= CodexReader.lifecycleReadBudget + 8 * 1_024 * 1_024 + 1)
        reader.files.resetCounters()
        #expect(reader.read(now: testNow.addingTimeInterval(2)) == reading)
        #expect(reader.files.opens == 0, "Recovered state is cached; unchanged polls do not reread history.")
    }

    @Test func lifecycleRecoveryContinuesAcrossPollsWithoutNewWrites() throws {
        let home = try CodexHome()
        let file = try home.install("open_turn")
        try home.lock([CodexFixtures.threadID("open_turn")])
        try appendHistory(65, to: file)
        try home.append(RolloutText.tokenCount(at: "2026-09-23T13:33:00Z", rateLimits: RolloutText.weekly(64)), to: file)
        let reader = home.reader()
        var reading = reader.read(now: testNow)
        #expect(reader.tailBytesRead <= CodexReader.lifecycleReadBudget + 8 * 1_024 * 1_024 + 1)
        for poll in 1...3 {
            let before = reader.tailBytesRead
            reading = reader.read(now: testNow.addingTimeInterval(Double(poll) * 2))
            #expect(reader.tailBytesRead - before <= CodexReader.lifecycleReadBudget)
        }
        #expect(reading.sessions.first?.activity == .working)
        reader.files.resetCounters()
        _ = reader.read(now: testNow.addingTimeInterval(8))
        #expect(reader.files.opens == 0)
    }

    @Test func completionInsideAnAppendGapOverridesTheCachedWorkingState() throws {
        let home = try CodexHome()
        let file = try home.install("open_turn")
        try home.lock([CodexFixtures.threadID("open_turn")])
        let reader = home.reader()
        #expect(reader.read(now: testNow).sessions.first?.activity == .working)
        try home.append(RolloutText.complete(at: "2026-09-23T13:31:00Z", turn: "t1"), to: file)
        try appendHistory(17, to: file)
        try home.append(RolloutText.tokenCount(at: "2026-09-23T13:33:00Z", rateLimits: RolloutText.weekly(64)), to: file)
        #expect(reader.read(now: testNow.addingTimeInterval(2)).sessions.first?.activity == .idle)
    }

    @Test func aLineOverFourMegabytesIsSkipped() throws {
        let home = try CodexHome()
        let thread = RolloutText.threadID(created: date("2026-09-23T13:00:00Z"), salt: 11)
        // A newer token_count padded past 4 MB: skipped unread, so the older reading stands.
        let huge = RolloutText.tokenCount(at: "2026-09-23T13:20:00.000Z", rateLimits: RolloutText.weekly(99))
            .replacingOccurrences(of: #""type":"token_count","#, with: #""type":"token_count","padding":"\#(String(repeating: "p", count: 5 * 1_024 * 1_024))","#)
        #expect(huge.utf8.count > 5 * 1_024 * 1_024)
        try home.installText(
            RolloutText.meta(thread, at: "2026-09-23T13:00:00.000Z")
                + RolloutText.started(at: "2026-09-23T13:00:01.000Z", turn: "t1")
                + RolloutText.tokenCount(at: "2026-09-23T13:10:00.000Z", rateLimits: RolloutText.weekly(42))
                + huge
                + RolloutText.complete(at: "2026-09-23T13:21:00.000Z", turn: "t1"),
            threadID: thread
        )
        try home.lock([thread])
        let reader = home.reader()
        let reading = reader.read(now: testNow)
        #expect(reading.usage.limits.first?.usedPercent == 42)
        #expect(reading.sessions.first?.activity == .idle)
        #expect(reader.tailBytesRead <= 8 * 1_024 * 1_024 + 1)
    }

    @Test func theNewestReadingIsFoundBeyondTheFirstWindow() throws {
        let home = try CodexHome()
        let thread = RolloutText.threadID(created: date("2026-09-23T12:00:00Z"), salt: 12)
        let url = home.paths.sessionsDirectory.appendingPathComponent("2026/09/23/rollout-2026-09-23T12-00-00-\(thread).jsonl")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: Data(RolloutText.meta(thread, at: "2026-09-23T12:00:00.000Z").utf8))
        // 19 MB of older history with an older reading at its start.
        try handle.write(contentsOf: Data(RolloutText.tokenCount(at: "2026-09-23T12:01:00.000Z", rateLimits: RolloutText.weekly(10)).utf8))
        let block = Data(String(repeating: filler(at: "2026-09-23T12:02:00.000Z", bytes: 64 * 1_024), count: 16).utf8)
        for _ in 0..<19 { try handle.write(contentsOf: block) }
        // The newest token_count, then ~1 MB of lines without any, so it sits beyond the first 256 KB.
        try handle.write(contentsOf: Data(RolloutText.started(at: "2026-09-23T13:00:00.000Z", turn: "t1").utf8))
        try handle.write(contentsOf: Data(RolloutText.tokenCount(at: "2026-09-23T13:30:00.000Z", rateLimits: RolloutText.weekly(64), used: 123_456).utf8))
        try handle.write(contentsOf: block)
        try handle.write(contentsOf: Data(RolloutText.complete(at: "2026-09-23T13:31:00.000Z", turn: "t1").utf8))
        try handle.close()
        try home.setModified(url, date("2026-09-23T13:31:01Z"))
        #expect(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize! > 20 * 1_000_000)

        try home.lock([thread])
        let reader = home.reader()
        let reading = reader.read(now: testNow)
        #expect(reading.usage.limits.first?.usedPercent == 64)
        #expect(reading.usage.limits.first?.observedAt == date("2026-09-23T13:30:00Z"))
        #expect(reading.sessions.first?.context?.usedTokens == 123_456)
        #expect(reading.sessions.first?.activity == .idle)
        // Never the whole file.
        #expect(reader.tailBytesRead <= 8 * 1_024 * 1_024 + 1)
    }

    @Test func largeFirstLinesAreReadUpToAMegabyte() throws {
        let home = try CodexHome()
        let thread = RolloutText.threadID(created: date("2026-09-23T13:00:00Z"), salt: 13)
        let meta = RolloutText.meta(thread, at: "2026-09-23T13:00:00.000Z", cwd: "/Users/me/code/big-head")
            .replacingOccurrences(of: #""source":"#, with: #""base_instructions":{"text":"\#(String(repeating: "b", count: 200_000))"},"source":"#)
        try home.installText(meta + RolloutText.started(at: "2026-09-23T13:30:00.000Z", turn: "t1"), threadID: thread)
        try home.lock([thread])
        #expect(home.reader().read(now: testNow).sessions.first?.name == "big-head")
    }

    /// 1.1 §11.1: a 2-second poll over 600 unchanged rollouts does at most one directory listing and no reads.
    @Test func aPollOverSixHundredUnchangedFilesListsOnceAndReadsNothing() throws {
        let home = try CodexHome()
        var locked: [String] = []
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        for index in 0..<600 {
            let created = date("2026-09-20T00:00:00Z").addingTimeInterval(TimeInterval(index * 400))
            let thread = RolloutText.threadID(created: created, salt: 1_000 + index)
            let at = created.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
            let later = created.addingTimeInterval(60).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
            let parts = utc.dateComponents([.year, .month, .day], from: created)
            let day = String(format: "%04ld/%02ld/%02ld", parts.year!, parts.month!, parts.day!)
            try home.installText(
                RolloutText.meta(thread, at: at) + RolloutText.started(at: at, turn: "t1")
                    + RolloutText.tokenCount(at: later, rateLimits: RolloutText.weekly(Double(index % 100))),
                threadID: thread, day: day
            )
            if index >= 595 { locked.append(thread) }
        }
        try home.lock(locked)
        let reader = home.reader()
        let now = date("2026-09-22T19:00:00Z")
        let first = reader.read(now: now)
        #expect(first.usage.status == .ok)
        #expect(first.sessions.count == 5)

        reader.files.resetCounters()
        let clock = ContinuousClock()
        var poll: CodexReading?
        let elapsed = clock.measure { poll = reader.read(now: now.addingTimeInterval(2)) }
        #expect(reader.files.listings <= 1)
        #expect(reader.files.opens == 0)
        #expect(poll == first)
        #expect(elapsed < .milliseconds(250), "poll took \(elapsed)")
    }
}
