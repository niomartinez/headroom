import Foundation
import HeadroomModel
import SetupKit
import Testing
@testable import HeadroomStore

/// Spec §4: files are re-parsed only when (size, mtime) changed.
@Suite struct SnapshotCacheTests {
    private func populatedTree() throws -> FixtureTree {
        let tree = try FixtureTree()
        try tree.writeDesktopHistory(
            [HistorySample(time: testNow - 10 * minute, fiveHour: 14, weekly: 89)], modified: testNow - 10 * minute)
        try tree.writeStatusLineLatest(
            fiveHour: (20, testNow + 2 * hour), weekly: (90, testNow + 72 * hour), modified: testNow - 20 * minute)
        try tree.writeRegistryEntry(sessionId: "desk-1", pid: 101, status: "busy")
        try tree.writeBridgeHook(sessionId: "term-1", pid: 201, event: "UserPromptSubmit", at: testNow - minute)
        try BridgeInstaller(claudeDirectory: tree.paths.claudeDirectory).install()
        return tree
    }

    @Test func unchangedFilesAreNotReadAgain() throws {
        let tree = try populatedTree()
        defer { tree.remove() }
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101, 201]))

        let first = builder.build(access: .full, now: testNow)
        let again = builder.build(access: .full, now: testNow + 2 * second)
        let andAgain = builder.build(access: .full, now: testNow + 4 * second)

        #expect(builder.statistics == SnapshotBuilder.Statistics(
            desktopReads: 1, terminalReads: 1, registryReads: 1, bridgeReads: 1, bridgeStateChecks: 1))
        #expect(first.plan == again.plan)
        #expect(again.sessions == andAgain.sessions)
        #expect(andAgain.terminalBridgeConnected)
    }

    @Test func aChangedSignatureIsReadAgain() throws {
        let tree = try populatedTree()
        defer { tree.remove() }
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101, 201]))
        _ = builder.build(access: .full, now: testNow)

        try tree.setModified(tree.paths.planUsageHistoryFile, testNow - 9 * minute)
        try tree.setModified(tree.paths.statusLineLatestFile, testNow - 19 * minute)
        try tree.writeRegistryEntry(sessionId: "desk-2", pid: 102, status: "idle")
        try tree.writeBridgeHook(sessionId: "term-1", pid: 201, event: "Stop", at: testNow)
        try tree.setModified(tree.paths.settingsFile, testNow)
        _ = builder.build(access: .full, now: testNow + 2 * second)

        #expect(builder.statistics == SnapshotBuilder.Statistics(
            desktopReads: 2, terminalReads: 2, registryReads: 2, bridgeReads: 2, bridgeStateChecks: 2))
    }

    /// The cache is keyed by the signature, not the content: a same-size rewrite that keeps the mtime is not
    /// noticed. (Real writers always move the mtime.)
    @Test func sameSizeAndMtimeKeepsTheCachedValue() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        let stamp = testNow - 10 * minute
        try tree.writeDesktopHistory([HistorySample(time: testNow - 10 * minute, fiveHour: 14, weekly: 89)], modified: stamp)
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe())
        #expect(builder.build(access: .full, now: testNow).plan.weekly?.usedPercent == 89)

        try tree.writeDesktopHistory([HistorySample(time: testNow - 10 * minute, fiveHour: 14, weekly: 77)], modified: stamp)

        #expect(builder.build(access: .full, now: testNow + 2 * second).plan.weekly?.usedPercent == 89)
        #expect(builder.statistics.desktopReads == 1)
    }

    @Test func aTranscriptIsReadOnceWhileUnchanged() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.writeRegistryEntry(sessionId: "desk-1", pid: 101, status: "busy")
        let transcript = try tree.writeTranscript(sessionId: "desk-1", usages: [("claude-opus-5-5", 100_000, testNow - minute)])
        // A whole-second mtime, so it can be restored exactly below.
        try tree.setModified(transcript, testNow - minute)
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101]))
        #expect(builder.build(access: .full, now: testNow).sessions.first?.context?.usedTokens == 100_000)

        // Replace the transcript's content without changing its size or mtime: a cached result proves no re-read.
        try tree.writeTranscript(sessionId: "desk-1", usages: [("claude-opus-5-5", 180_000, testNow - minute)])
        try tree.setModified(transcript, testNow - minute)

        #expect(builder.build(access: .full, now: testNow + 2 * second).sessions.first?.context?.usedTokens == 100_000)
    }

    // MARK: Terminal limits and their transcript

    /// statusline-latest.json whose payload names a transcript whose newest reply is `reply`.
    private func terminalTree(reply: Date) throws -> (FixtureTree, transcript: URL) {
        let tree = try FixtureTree()
        let transcript = try tree.writeTranscript(sessionId: "term-1", usages: [("claude-haiku-4-5", 50_000, reply)])
        try tree.writeStatusLineLatest(
            fiveHour: (20, testNow + 2 * hour), weekly: (90, testNow + 72 * hour), modified: testNow - minute,
            transcriptPath: transcript.path
        )
        return (tree, transcript)
    }

    /// The terminal readings are dated by the transcript's newest reply. When the status line writes the file
    /// before the reply that produced its numbers reaches the transcript, the reply is seen on the next build,
    /// without waiting for another status line write.
    @Test func aReplyReachingTheTranscriptLaterIsSeen() throws {
        let (tree, _) = try terminalTree(reply: testNow - 10 * minute)
        defer { tree.remove() }
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe())
        #expect(builder.build(access: .full, now: testNow).plan.fiveHour?.observedAt == testNow - 10 * minute)

        try tree.writeTranscript(sessionId: "term-1", usages: [
            ("claude-haiku-4-5", 50_000, testNow - 10 * minute), ("claude-haiku-4-5", 52_000, testNow - 2 * minute),
        ])
        let plan = builder.build(access: .full, now: testNow + 2 * second).plan

        #expect(plan.fiveHour?.observedAt == testNow - 2 * minute)
        #expect(plan.weekly?.observedAt == testNow - 2 * minute)
        #expect(builder.statistics.terminalReads == 2)
    }

    @Test func anUnchangedTranscriptKeepsTheCachedReading() throws {
        let (tree, _) = try terminalTree(reply: testNow - 10 * minute)
        defer { tree.remove() }
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe())

        let first = builder.build(access: .full, now: testNow).plan
        let again = builder.build(access: .full, now: testNow + 2 * second).plan

        #expect(first == again)
        #expect(builder.statistics.terminalReads == 1)
    }

    /// A transcript that appears only after the reading (the payload named it before it was written) is noticed.
    @Test func aTranscriptAppearingLaterIsSeen() throws {
        let (tree, transcript) = try terminalTree(reply: testNow - 10 * minute)
        defer { tree.remove() }
        try FileManager.default.removeItem(at: transcript)
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe())
        // Without a transcript the file's mtime dates the readings.
        #expect(builder.build(access: .full, now: testNow).plan.fiveHour?.observedAt == testNow - minute)

        try tree.writeTranscript(sessionId: "term-1", usages: [("claude-haiku-4-5", 50_000, testNow - 3 * minute)])

        #expect(builder.build(access: .full, now: testNow + 2 * second).plan.fiveHour?.observedAt == testNow - 3 * minute)
    }
}

/// Spec §2.6 state → `terminalBridgeConnected`, recomputed only when settings.json or bridge.sh change.
@Suite struct BridgeConnectionTests {
    @Test func notInstalled() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.write(#"{"theme":"dark"}"#, to: tree.paths.settingsFile)

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe()).build(access: .full, now: testNow)

        #expect(!snapshot.terminalBridgeConnected)
    }

    @Test func installedThenDisconnected() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        let installer = BridgeInstaller(claudeDirectory: tree.paths.claudeDirectory)
        try installer.install()
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe())

        #expect(builder.build(access: .full, now: testNow).terminalBridgeConnected)
        #expect(builder.bridgeInstallState == .installed)
        #expect(builder.build(access: .full, now: testNow + 2 * second).terminalBridgeConnected)
        #expect(builder.statistics.bridgeStateChecks == 1)

        try installer.uninstall()
        #expect(!builder.build(access: .full, now: testNow + 4 * second).terminalBridgeConnected)
        #expect(builder.bridgeInstallState == .notInstalled)
        #expect(builder.statistics.bridgeStateChecks == 2)
    }

    @Test func outdatedCountsAsConnected() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        let installer = BridgeInstaller(claudeDirectory: tree.paths.claudeDirectory)
        try installer.install()
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe())
        #expect(builder.build(access: .full, now: testNow).terminalBridgeConnected)

        // Only bridge.sh changes (an older script version): the state must be recomputed.
        try tree.write("#!/bin/bash\n# headroom-bridge v0\nexit 0\n", to: installer.scriptFile)
        let snapshot = builder.build(access: .full, now: testNow + 2 * second)

        #expect(builder.bridgeInstallState == .outdated)
        #expect(snapshot.terminalBridgeConnected)
    }

    @Test func unreadableSettingsAreNotConnected() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try tree.write("{ not json", to: tree.paths.settingsFile)

        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe())
        let snapshot = builder.build(access: .full, now: testNow)

        #expect(!snapshot.terminalBridgeConnected)
        guard case .settingsUnreadable = builder.bridgeInstallState else {
            Issue.record("expected settingsUnreadable, got \(String(describing: builder.bridgeInstallState))")
            return
        }
    }

    @Test func unknownWithoutClaudeFolderAccess() throws {
        let tree = try FixtureTree()
        defer { tree.remove() }
        try BridgeInstaller(claudeDirectory: tree.paths.claudeDirectory).install()
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe())

        let snapshot = builder.build(access: AccessState(claudeDirectoryReadable: false, desktopDirectoryReadable: true), now: testNow)

        #expect(!snapshot.terminalBridgeConnected)
        #expect(builder.bridgeInstallState == nil)
    }
}
