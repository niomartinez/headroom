import Foundation
import HeadroomModel
import SetupKit
import Testing
@testable import HeadroomStore

/// Folder access (spec §2.1, §4): an unreadable folder becomes an issue and nothing under it is read.
@Suite struct SnapshotAccessTests {
    /// A tree with data in every source, so a test can tell which ones were skipped.
    private func populatedTree() throws -> FixtureTree {
        let tree = try FixtureTree()
        try tree.writeDesktopHistory([HistorySample(time: testNow - 10 * minute, fiveHour: 14, weekly: 89)])
        try tree.writeStatusLineLatest(
            fiveHour: (20, testNow + 2 * hour), weekly: (90, testNow + 72 * hour), modified: testNow - minute)
        try tree.writeRegistryEntry(sessionId: "desk-1", pid: 101, status: "busy")
        try tree.writeBridgeHook(sessionId: "term-1", pid: 202, event: "UserPromptSubmit", at: testNow - minute)
        try BridgeInstaller(claudeDirectory: tree.paths.claudeDirectory).install()
        return tree
    }

    @Test func fullAccessReadsEverySource() throws {
        let tree = try populatedTree()
        defer { tree.remove() }

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101, 202]))
            .build(access: .full, now: testNow)

        #expect(snapshot.plan.weekly?.source == .terminal)
        #expect(Set(snapshot.sessions.map(\.id)) == ["desk-1", "term-1"])
        #expect(snapshot.terminalBridgeConnected)
        #expect(snapshot.issues.isEmpty)
    }

    @Test func noAccessAtAll() throws {
        let tree = try populatedTree()
        defer { tree.remove() }

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101, 202]))
            .build(access: .none, now: testNow)

        #expect(snapshot.issues == [.claudeCodeFolderUnavailable, .desktopFolderUnavailable])
        #expect(snapshot.plan == .empty)
        #expect(snapshot.sessions.isEmpty)
        #expect(!snapshot.terminalBridgeConnected)
        #expect(snapshot.generatedAt == testNow)
    }

    @Test func noClaudeFolderAccessSkipsEverythingUnderIt() throws {
        let tree = try populatedTree()
        defer { tree.remove() }
        let access = AccessState(claudeDirectoryReadable: false, desktopDirectoryReadable: true)

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101, 202]))
            .build(access: access, now: testNow)

        #expect(snapshot.issues == [.claudeCodeFolderUnavailable])
        // The terminal reading lives under ~/.claude: only the desktop one is left.
        #expect(snapshot.plan.weekly?.source == .desktopApp)
        #expect(snapshot.plan.weekly?.usedPercent == 89)
        #expect(snapshot.sessions.isEmpty)
        #expect(!snapshot.terminalBridgeConnected)
    }

    @Test func noDesktopFolderAccessWithTheAppInstalled() throws {
        let tree = try populatedTree()
        defer { tree.remove() }
        let access = AccessState(claudeDirectoryReadable: true, desktopDirectoryReadable: false, desktopAppInstalled: true)

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101, 202]))
            .build(access: access, now: testNow)

        #expect(snapshot.issues == [.desktopFolderUnavailable])
        #expect(snapshot.plan.weekly?.source == .terminal)
        #expect(snapshot.plan.extraUsagePercent == nil)
        #expect(snapshot.sessions.count == 2)
    }

    @Test func desktopAppNotInstalledIsNotAnIssue() throws {
        let tree = try populatedTree()
        defer { tree.remove() }
        let access = AccessState(claudeDirectoryReadable: true, desktopDirectoryReadable: false, desktopAppInstalled: false)

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101, 202]))
            .build(access: access, now: testNow)

        #expect(snapshot.issues.isEmpty)
        #expect(snapshot.plan.weekly?.source == .terminal)
        #expect(snapshot.terminalBridgeConnected)
    }

    @Test func desktopAppNotInstalledButFolderReadableIsStillRead() throws {
        let tree = try populatedTree()
        defer { tree.remove() }
        try FileManager.default.removeItem(at: tree.paths.statusLineLatestFile)
        let access = AccessState(claudeDirectoryReadable: true, desktopDirectoryReadable: true, desktopAppInstalled: false)

        let snapshot = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101, 202]))
            .build(access: access, now: testNow)

        #expect(snapshot.issues.isEmpty)
        #expect(snapshot.plan.weekly?.source == .desktopApp)
    }

    @Test func accessComingBackReadsAgain() throws {
        let tree = try populatedTree()
        defer { tree.remove() }
        let builder = SnapshotBuilder(paths: tree.paths, probe: FakeProcessProbe(alive: [101, 202]))

        _ = builder.build(access: .none, now: testNow)
        let snapshot = builder.build(access: .full, now: testNow + 2 * second)

        #expect(snapshot.issues.isEmpty)
        #expect(snapshot.sessions.count == 2)
        #expect(snapshot.terminalBridgeConnected)
        #expect(snapshot.plan.weekly != nil)
    }
}
