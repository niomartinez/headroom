import Foundation
import HeadroomModel
import Testing
@testable import CodexKit

/// Codex sessions (1.1 §3.5): which threads, liveness, activity, context, names.
@Suite struct CodexSessionsTests {
    private func id(_ fixture: String) -> String { "codex:" + CodexFixtures.threadID(fixture) }

    /// The shown session ids.
    private func shown(_ reading: CodexReading) -> Set<String> { Set(reading.sessions.map(\.id)) }

    // MARK: - Liveness table

    @Test func lockedThreadsShowWhileCodexRuns() throws {
        let home = try CodexHome()
        try home.install("open_turn")
        try home.install("aborted")
        try home.lock([CodexFixtures.threadID("open_turn")], coordination: true)
        let reading = home.reader(running: true).read(now: testNow)
        #expect(shown(reading) == [id("open_turn")])
        #expect(reading.sessions.allSatisfy { $0.tool == .codex && $0.pid == nil && $0.transcriptPath == nil })
    }

    @Test func locksLeftBehindAreIgnoredWhenCodexIsNotRunning() throws {
        let home = try CodexHome()
        try home.install("open_turn")
        try home.lock([CodexFixtures.threadID("open_turn")])
        let reader = home.reader(running: false)
        #expect(reader.read(now: testNow).sessions.isEmpty)
        // The limits search's tail read only: no head read for a session.
        #expect(reader.files.opens == 1)
    }

    @Test func withoutAProcessListLockedThreadsShowForTwoHours() throws {
        let home = try CodexHome()
        try home.install("open_turn")  // newest event 13:31
        try home.install("plus_5h_weekly")  // newest event 10:02
        try home.lock([CodexFixtures.threadID("open_turn"), CodexFixtures.threadID("plus_5h_weekly")])
        let reading = home.reader(running: nil).read(now: testNow)
        #expect(shown(reading) == [id("open_turn")])
    }

    @Test func threadsWithoutALockAreNotShown() throws {
        let home = try CodexHome()
        try home.install("open_turn")
        try home.lock([])
        #expect(home.reader(running: true).read(now: testNow).sessions.isEmpty)
        #expect(home.reader(running: nil).read(now: testNow).sessions.isEmpty)
    }

    @Test func withoutALocksFolderRecentThreadsShow() throws {
        let home = try CodexHome()
        try home.install("open_turn")  // newest event 13:31 (9 min)
        try home.install("aborted")  // 13:26 (14 min)
        try home.install("error_usage_limit")  // 13:20 (20 min)
        #expect(shown(home.reader(running: true).read(now: testNow)) == [id("open_turn"), id("aborted")])
        #expect(shown(home.reader(running: nil).read(now: testNow)) == [id("open_turn"), id("aborted")])
        #expect(home.reader(running: false).read(now: testNow).sessions.isEmpty)
    }

    @Test func aRecentlyTouchedFileWithOldEventsIsNotRecent() throws {
        let home = try CodexHome()
        // Rewritten: modified now, newest event 10:02.
        try home.install("plus_5h_weekly", modified: testNow.addingTimeInterval(-60))
        #expect(home.reader(running: true).read(now: testNow).sessions.isEmpty)
    }

    @Test func idleThreadsHideAfterEightHours() throws {
        let home = try CodexHome()
        try home.install("open_turn")  // working since 13:30
        try home.install("aborted")  // idle since 13:26
        try home.lock([CodexFixtures.threadID("open_turn"), CodexFixtures.threadID("aborted")])
        let later = date("2026-09-23T21:40:00Z")
        let reading = home.reader(running: true).read(now: later)
        #expect(shown(reading) == [id("open_turn")])
        #expect(shown(home.reader(running: true).read(now: date("2026-09-23T21:20:00Z"))) == [id("open_turn"), id("aborted")])
    }

    @Test func codexIsOnlyAskedAboutWhenAThreadCouldShow() throws {
        final class CountingRuntime: CodexRuntimeProbing, @unchecked Sendable {
            var calls = 0
            func codexRunning() -> Bool? {
                calls += 1
                return true
            }
        }
        let home = try CodexHome()
        try home.install("plus_5h_weekly")  // old, and no locks folder
        let runtime = CountingRuntime()
        let reader = CodexReader(codexHome: home.root, runtime: runtime)
        _ = reader.read(now: testNow)
        #expect(runtime.calls == 0)
        try home.lock([CodexFixtures.threadID("plus_5h_weekly")])
        #expect(reader.read(now: testNow.addingTimeInterval(2)).sessions.count == 1)
        #expect(runtime.calls == 1)
    }

    @Test func coordinationAndStaleLocksAreHarmless() throws {
        let home = try CodexHome()
        try home.install("open_turn")
        let missing = RolloutText.threadID(created: date("2026-09-23T12:00:00Z"), salt: 9)
        try home.lock([CodexFixtures.threadID("open_turn"), missing], coordination: true)
        let reader = home.reader(running: true)
        #expect(reader.listLocks() == .present([CodexFixtures.threadID("open_turn"), missing]))
        #expect(shown(reader.read(now: testNow)) == [id("open_turn")])
    }

    // MARK: - Which threads

    @Test func onlyRootNativeThreadsAreShown() throws {
        let home = try CodexHome()
        let fixtures = ["subagent", "guardian", "exec_source", "cli_source", "open_turn"]
        for fixture in fixtures { try home.install(fixture) }
        try home.lock(fixtures.map(CodexFixtures.threadID))
        #expect(shown(home.reader().read(now: testNow)) == [id("cli_source"), id("open_turn")])
    }

    @Test func importedThreadsShowOnlyWhenContinuedInCodex() throws {
        let home = try CodexHome()
        try home.install("imported_claude")
        try home.install("imported_claude_continued")
        try home.installImports(CodexFixtures.file("external_agent_session_imports.json"))
        try home.lock([CodexFixtures.threadID("imported_claude"), CodexFixtures.threadID("imported_claude_continued")])
        let reading = home.reader().read(now: testNow)
        #expect(shown(reading) == [id("imported_claude_continued")])
        // Without the imports file both are native threads.
        try FileManager.default.removeItem(at: home.paths.importsFile)
        #expect(shown(home.reader().read(now: testNow)).count == 2)
    }

    @Test func rolloutIDSuffixesKeepTheThreadID() throws {
        let home = try CodexHome()
        try home.install("rolloutid_suffix", rolloutID: "01a0cf00-0000-7000-8000-00000000abcd")
        try home.lock([CodexFixtures.threadID("rolloutid_suffix")])
        let session = try #require(home.reader().read(now: testNow).sessions.first)
        #expect(session.id == id("rolloutid_suffix"))
        #expect(session.name == "forked")
    }

    // MARK: - Activity

    @Test func anOpenTurnIsWorking() throws {
        let home = try CodexHome()
        try home.install("open_turn")
        try home.install("aborted")
        try home.install("error_usage_limit")
        try home.lock(["open_turn", "aborted", "error_usage_limit"].map(CodexFixtures.threadID))
        let sessions = Dictionary(uniqueKeysWithValues: home.reader().read(now: testNow).sessions.map { ($0.id, $0) })
        #expect(sessions[id("open_turn")]?.activity == .working)
        #expect(sessions[id("open_turn")]?.activitySince == date("2026-09-23T13:30:00.500Z"))
        #expect(sessions[id("aborted")]?.activity == .idle)
        #expect(sessions[id("aborted")]?.activitySince == date("2026-09-23T13:26:00Z"))
        #expect(sessions[id("error_usage_limit")]?.activity == .idle)
        #expect(sessions.values.allSatisfy { $0.activity != .waitingForInput })
    }

    @Test func finishingATurnMakesTheThreadIdleWithAnAppendedRead() throws {
        let home = try CodexHome()
        let url = try home.install("open_turn")
        try home.lock([CodexFixtures.threadID("open_turn")])
        let reader = home.reader()
        #expect(reader.read(now: testNow).sessions.first?.activity == .working)

        try home.append(RolloutText.complete(at: "2026-09-23T13:40:01.000Z", turn: "t2"), to: url, modified: date("2026-09-23T13:40:02Z"))
        let before = reader.tailBytesRead
        reader.files.resetCounters()
        let session = try #require(reader.read(now: testNow.addingTimeInterval(2)).sessions.first)
        #expect(session.activity == .idle)
        #expect(session.activitySince == date("2026-09-23T13:40:01Z"))
        // A poll, not a walk: the locks listing only, and only the appended line read.
        #expect(reader.files.listings == 1)
        #expect(reader.tailBytesRead - before < 200)
        // The context survives from the earlier read.
        #expect(session.context?.usedTokens == 100_000)

        try home.append(RolloutText.started(at: "2026-09-23T13:41:00.000Z", turn: "t3"), to: url, modified: date("2026-09-23T13:41:01Z"))
        let again = try #require(reader.read(now: testNow.addingTimeInterval(64)).sessions.first)
        #expect(again.activity == .working)
        #expect(again.activitySince == date("2026-09-23T13:41:00Z"))
    }

    @Test func unknownLineTypesAreSkipped() throws {
        let home = try CodexHome()
        try home.install("unknown_line_types")
        try home.lock([CodexFixtures.threadID("unknown_line_types")])
        let session = try #require(home.reader().read(now: testNow).sessions.first)
        #expect(session.activity == .idle)
        #expect(session.activitySince == date("2026-09-23T13:19:30Z"))
        #expect(session.context?.usedTokens == 50_000)
    }

    // MARK: - Context

    @Test func contextUsesCodexsOwnFormula() throws {
        let home = try CodexHome()
        let fixtures = ["plus_5h_weekly", "estimate_token_count", "context_over_window", "cli_source"]
        for fixture in fixtures { try home.install(fixture) }
        try home.lock(fixtures.map(CodexFixtures.threadID))
        let sessions = Dictionary(uniqueKeysWithValues: home.reader().read(now: testNow).sessions.map { ($0.id, $0) })

        let plus = try #require(sessions[id("plus_5h_weekly")]?.context)
        #expect(plus.usedTokens == 150_000)
        #expect(plus.windowTokens == 258_400)
        #expect(plus.windowIsExact)
        #expect(!plus.windowIsAssumed)
        #expect(plus.baselineTokens == 12_000)
        #expect(plus.model == "gpt-6-astra")
        #expect(plus.observedAt == date("2026-09-23T10:02:00Z"))
        #expect(abs(plus.percent - Double(150_000 - 12_000) / Double(258_400 - 12_000) * 100) < 1e-9)

        // An estimate line (input and output 0), with the window from task_started.
        let estimate = try #require(sessions[id("estimate_token_count")]?.context)
        #expect(estimate.usedTokens == 90_000)
        #expect(estimate.windowTokens == 200_000)
        #expect(!estimate.windowIsExact)
        #expect(!estimate.windowIsAssumed)

        let over = try #require(sessions[id("context_over_window")]?.context)
        #expect(over.usedTokens == 272_000)
        #expect(over.percent == 100)

        #expect(sessions[id("cli_source")]?.context?.model == "gpt-6-astra-mini")
    }

    @Test func withoutAnyWindowItIsAssumed() throws {
        let home = try CodexHome()
        let thread = RolloutText.threadID(created: date("2026-09-23T13:30:00Z"), salt: 4)
        try home.installText(
            RolloutText.meta(thread, at: "2026-09-23T13:30:00.000Z")
                + RolloutText.started(at: "2026-09-23T13:30:01.000Z", turn: "t1")
                + RolloutText.tokenCount(at: "2026-09-23T13:31:00.000Z", used: 30_000, window: nil),
            threadID: thread
        )
        try home.lock([thread])
        let context = try #require(home.reader().read(now: testNow).sessions.first?.context)
        #expect(context.windowTokens == 258_400)
        #expect(context.windowIsAssumed)
        #expect(!context.windowIsExact)
        #expect(context.model == nil)
    }

    // MARK: - Names and origin

    @Test func namesComeFromTheSessionIndexThenTheFolder() throws {
        let home = try CodexHome()
        let fixtures = ["open_turn", "aborted", "cli_source", "error_usage_limit"]
        for fixture in fixtures { try home.install(fixture) }
        try home.installSessionIndex(CodexFixtures.file("session_index_duplicates.jsonl"))
        try home.lock(fixtures.map(CodexFixtures.threadID))
        let reader = home.reader()
        let sessions = Dictionary(uniqueKeysWithValues: reader.read(now: testNow).sessions.map { ($0.id, $0) })

        // The newest line per id wins, trimmed.
        #expect(sessions[id("open_turn")]?.name == "Ship the release")
        // Its newest name is empty: the folder name.
        #expect(sessions[id("aborted")]?.name == "app")
        // Two rows share a name: their start times tell them apart.
        #expect(sessions[id("cli_source")]?.name == "Fix login bug · " + reader.shortTime(date("2026-09-23T13:00:00Z")))
        #expect(sessions[id("error_usage_limit")]?.name == "Fix login bug · " + reader.shortTime(date("2026-09-23T13:14:00Z")))
        #expect(reader.shortTime(date("2026-09-23T13:14:00Z")).hasPrefix("1:14"))
    }

    @Test func aRenamedThreadIsReadFromTheAppendedIndex() throws {
        let home = try CodexHome()
        try home.install("open_turn")
        try home.installSessionIndex(CodexFixtures.file("session_index_duplicates.jsonl"))
        try home.lock([CodexFixtures.threadID("open_turn")])
        let reader = home.reader()
        #expect(reader.read(now: testNow).sessions.first?.name == "Ship the release")
        try home.append(#"{"id":"\#(CodexFixtures.threadID("open_turn"))","thread_name":"Renamed","updated_at":"2026-09-23T13:40:01Z"}"# + "\n",
                        to: home.paths.sessionIndexFile)
        #expect(reader.read(now: testNow.addingTimeInterval(2)).sessions.first?.name == "Renamed")
    }

    @Test func originFollowsTheSource() throws {
        let home = try CodexHome()
        try home.install("cli_source")
        try home.install("open_turn")
        try home.lock(["cli_source", "open_turn"].map(CodexFixtures.threadID))
        let sessions = Dictionary(uniqueKeysWithValues: home.reader().read(now: testNow).sessions.map { ($0.id, $0) })
        let cli = try #require(sessions[id("cli_source")])
        #expect(cli.origin == .terminal)
        #expect(cli.projectPath == "/Users/me/code/tool")
        #expect(cli.startedAt == date("2026-09-23T13:00:00Z"))
        #expect(sessions[id("open_turn")]?.origin == .desktop)
    }

    // MARK: - Finding a thread's file (§3.5)

    @Test func threadFilesAreFoundFromTheirUUIDv7NearMidnight() throws {
        let home = try CodexHome()
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        // Created 23:59:59.5 in Los Angeles, so Codex filed it under that local day.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = losAngeles
        let created = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 23, minute: 59, second: 59, nanosecond: 500_000_000))!
        let thread = RolloutText.threadID(created: created, salt: 5)
        try home.installText(RolloutText.meta(thread, at: "2026-09-24T06:59:59.500Z"), threadID: thread, day: "2026/09/23")

        let reader = home.reader()
        // Here, it is already the 24th (UTC), and the next day in Manila: the neighbouring day finds it.
        for zone in ["America/Los_Angeles", "UTC", "Asia/Manila"] {
            reader.calendar.timeZone = TimeZone(identifier: zone)!
            #expect(reader.locateRollout(threadID: thread)?.threadID == thread, "\(zone)")
        }
        // A thread from another day isn't there.
        #expect(reader.locateRollout(threadID: RolloutText.threadID(created: created.addingTimeInterval(-3 * 86_400), salt: 6)) == nil)
    }

    @Test func aLockedThreadCreatedAfterTheWalkIsFound() throws {
        let home = try CodexHome()
        try home.install("open_turn")
        let thread = RolloutText.threadID(created: date("2026-09-23T13:39:00Z"), salt: 8)
        try home.lock([CodexFixtures.threadID("open_turn"), thread])
        let reader = home.reader()
        #expect(reader.read(now: testNow).sessions.count == 1)
        // Codex takes the lock first and writes the rollout later; no walk is due yet.
        try home.installText(
            RolloutText.meta(thread, at: "2026-09-23T13:39:00.000Z") + RolloutText.started(at: "2026-09-23T13:40:00.000Z", turn: "t1"),
            threadID: thread
        )
        let sessions = reader.read(now: testNow.addingTimeInterval(12)).sessions
        #expect(Set(sessions.map(\.id)) == [id("open_turn"), "codex:\(thread)"])
    }
}
