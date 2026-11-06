import Foundation
import HeadroomModel
import Testing
@testable import HeadroomStore

/// Context per session (spec §2.3): transcript tail + window size (exact, learned, or by rule).
@Suite struct SnapshotContextTests {
    @Test func desktopSessionGetsContextFromItsTranscript() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        let replyTime = testNow - 2 * minute
        try tree.writeRegistryEntry(sessionId: "desk-1", pid: 101, status: "busy")
        let transcript = try tree.writeTranscript(sessionId: "desk-1", usages: [
            ("claude-opus-5-5", 90_000, testNow - 5 * minute),
            ("claude-opus-5-5", 250_000, replyTime),
        ])

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101]))
            .build(access: .full, now: testNow)

        let session = try #require(snapshot.sessions.first)
        let context = try #require(session.context)
        #expect(context.usedTokens == 250_000)
        #expect(context.windowTokens == 1_000_000)
        #expect(context.model == "claude-opus-5-5")
        #expect(!context.windowIsExact)
        #expect(context.observedAt == replyTime)
        #expect(context.percent == 25)
        #expect(session.transcriptPath == transcript.path)
    }

    @Test func terminalSessionUsesItsOwnStatusLineWindowExactly() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        let transcript = try tree.writeTranscript(
            sessionId: "term-1", projectFolder: "-Users-tester-code-terminal-tool",
            usages: [("claude-opus-5-5", 50_000, testNow - minute)])
        try tree.writeBridgeHook(
            sessionId: "term-1", pid: 201, event: "Stop", at: testNow - minute, transcriptPath: transcript.path)
        try tree.writeBridgeStatusLine(
            sessionId: "term-1", pid: 201, at: testNow - minute, model: "claude-opus-5-5",
            contextWindowSize: 200_000, transcriptPath: transcript.path)

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [201]))
            .build(access: .full, now: testNow)

        let context = try #require(snapshot.sessions.first?.context)
        #expect(context.windowTokens == 200_000)
        #expect(context.windowIsExact)
        #expect(context.percent == 25)
    }

    @Test func desktopSessionLearnsTheWindowFromAnotherSessionsStatusLine() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeRegistryEntry(sessionId: "desk-1", pid: 101, status: "idle")
        try tree.writeTranscript(sessionId: "desk-1", usages: [("claude-haiku-4-5", 150_000, testNow - minute)])
        // A terminal session (long gone) ran the same model with a 1M window: the "[1m]" suffix is ignored.
        try tree.writeBridgeStatusLine(
            sessionId: "term-old", pid: 999, at: testNow - 3 * hour, model: "claude-haiku-4-5[1m]",
            contextWindowSize: 1_000_000)

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101]))
            .build(access: .full, now: testNow)

        #expect(snapshot.sessions.map(\.id) == ["desk-1"])
        let context = try #require(snapshot.sessions.first?.context)
        #expect(context.windowTokens == 1_000_000)
        #expect(!context.windowIsExact)
        #expect(context.percent == 15)
    }

    @Test func learnedWindowLookupIgnoresTheSuffixOnTheTranscriptModelToo() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeRegistryEntry(sessionId: "desk-1", pid: 101, status: "idle")
        try tree.writeTranscript(sessionId: "desk-1", usages: [("claude-sonnet-4-6[1m]", 100_000, testNow - minute)])
        try tree.writeBridgeStatusLine(
            sessionId: "term-old", pid: 999, at: testNow - 3 * hour, model: "claude-sonnet-4-6",
            contextWindowSize: 400_000)

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101]))
            .build(access: .full, now: testNow)

        let context = try #require(snapshot.sessions.first?.context)
        #expect(context.windowTokens == 400_000)
        #expect(context.percent == 25)
    }

    @Test func aLearnedWindowSmallerThanTheUsageIsIgnored() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeRegistryEntry(sessionId: "desk-1", pid: 101, status: "idle")
        try tree.writeTranscript(sessionId: "desk-1", usages: [("claude-haiku-4-5", 300_000, testNow - minute)])
        try tree.writeBridgeStatusLine(
            sessionId: "term-old", pid: 999, at: testNow - 3 * hour, model: "claude-haiku-4-5",
            contextWindowSize: 200_000)

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101]))
            .build(access: .full, now: testNow)

        // The rules then say: more than 200k used → a 1M window.
        #expect(snapshot.sessions.first?.context?.windowTokens == 1_000_000)
    }

    @Test func withoutAnyStatusLineTheRulesDecide() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeRegistryEntry(sessionId: "desk-1", pid: 101, status: "idle")
        try tree.writeTranscript(sessionId: "desk-1", usages: [("claude-haiku-4-5", 50_000, testNow - minute)])

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101]))
            .build(access: .full, now: testNow)

        #expect(snapshot.sessions.first?.context?.windowTokens == 200_000)
        #expect(snapshot.sessions.first?.context?.percent == 25)
    }

    @Test func sessionWithoutATranscriptHasNoContext() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeRegistryEntry(sessionId: "desk-1", pid: 101, status: "idle")

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101]))
            .build(access: .full, now: testNow)

        #expect(snapshot.sessions.count == 1)
        #expect(snapshot.sessions.first?.context == nil)
        #expect(snapshot.sessions.first?.transcriptPath == nil)
    }

    @Test func contextFollowsTheTranscript() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeRegistryEntry(sessionId: "desk-1", pid: 101, status: "busy")
        try tree.writeTranscript(sessionId: "desk-1", usages: [("claude-opus-5-5", 100_000, testNow - minute)])
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101]))
        #expect(builder.build(access: .full, now: testNow).sessions.first?.context?.usedTokens == 100_000)

        try tree.writeTranscript(sessionId: "desk-1", usages: [
            ("claude-opus-5-5", 100_000, testNow - minute),
            ("claude-opus-5-5", 120_000, testNow + second),
        ])

        #expect(builder.build(access: .full, now: testNow + 2 * second).sessions.first?.context?.usedTokens == 120_000)
    }
}
