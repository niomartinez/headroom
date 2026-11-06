import Darwin
import Foundation
import HeadroomModel
import HeadroomStore
import SetupKit
import os
import Testing

/// The poll's background half (spec §4): probing access, building the snapshot and reading the
/// bridge state, all off the main thread.
@Suite struct SnapshotWorkerTests {
    private func makeHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeadroomSnapshotWorkerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func check(home: URL, claudeGranted: Bool = true, desktopGranted: Bool = false) -> AccessCheck {
        let paths = ClaudePaths.standard(home: home)
        return AccessCheck(
            paths: paths,
            claudeGranted: claudeGranted,
            desktopGranted: desktopGranted,
            claudeCodeLocation: paths.claudeDirectory,
            desktopAppInstalled: desktopGranted,
            generation: 0
        )
    }

    /// A made-up `plan-usage-history.json`: (seconds before `now`, org, weekly percent) per sample.
    private func writeDesktopHistory(_ samples: [(ago: TimeInterval, org: String, weekly: Double)], home: URL, now: Date) throws {
        let file = ClaudePaths.standard(home: home).planUsageHistoryFile
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let items = samples.map { sample in
            let millis = Int64(((now.timeIntervalSince1970 - sample.ago) * 1000).rounded())
            return #"{"t":\#(millis),"org":"\#(sample.org)","u":{"fh":10,"sd":\#(sample.weekly)}}"#
        }
        try Data(#"{"version":2,"samples":[\#(items.joined(separator: ","))]}"#.utf8).write(to: file)
    }

    /// Switching accounts in the Claude app swaps in the other account's usage (spec §2.1). The
    /// poll hands back the account each snapshot was built with, so the pill doesn't announce the
    /// switch as a limit crossing (F18).
    @Test func theDesktopAccountComesWithItsSnapshot() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: ClaudePaths.standard(home: home).claudeDirectory, withIntermediateDirectories: true)
        let now = Date()
        let orgA = (ago: 17 * 3600.0, org: "org-a", weekly: 100.0)
        let orgB = (ago: 600.0, org: "org-b", weekly: 87.0)
        let worker = SnapshotWorker()

        try writeDesktopHistory([orgA, orgB], home: home, now: now)
        let before = await worker.refresh(check: check(home: home, desktopGranted: true), lookUpDesktopApp: { true }, now: now - 540)
        #expect(before.desktopAccount == "org-b")
        #expect(before.snapshot.plan.weekly?.usedPercent == 87)

        try writeDesktopHistory([orgA, orgB, (ago: 240, org: "org-a", weekly: 100)], home: home, now: now)
        let after = await worker.refresh(check: check(home: home, desktopGranted: true), lookUpDesktopApp: { true }, now: now)
        #expect(after.desktopAccount == "org-a")
        #expect(after.snapshot.plan.weekly?.usedPercent == 100)

        #expect(MomentDetector.moments(
            previous: before.snapshot, previousDesktopAccount: before.desktopAccount,
            current: after.snapshot, currentDesktopAccount: after.desktopAccount
        ).isEmpty)
        // What the pill announced before it knew the accounts: "Weekly limit reached".
        #expect(MomentDetector.moments(previous: before.snapshot, current: after.snapshot) == [.limitCrossed(kind: .weekly, percent: 100)])
    }

    @Test func noDesktopAccountWithoutTheClaudeAppsFolder() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeDesktopHistory([(ago: 60, org: "org-a", weekly: 40)], home: home, now: Date())

        let result = await SnapshotWorker().refresh(check: check(home: home), lookUpDesktopApp: { false }, now: Date())
        #expect(result.desktopAccount == nil)
    }

    /// A Disconnect that couldn't delete everything leaves `~/.claude/headroom`, or a renamed copy
    /// it was deleting, while settings.json is already clean. The poll says so, so Settings can
    /// offer Disconnect again (F09).
    @Test func leftoverBridgeFilesAreReported() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let claude = ClaudePaths.standard(home: home).claudeDirectory
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try Data(#"{"model":"opus"}"#.utf8).write(to: claude.appendingPathComponent("settings.json"))
        let worker = SnapshotWorker()

        let clean = await worker.refresh(check: check(home: home), lookUpDesktopApp: { false }, now: Date())
        #expect(clean.bridgeState == .notInstalled)
        #expect(!clean.hasBridgeLeftovers)

        let interrupted = claude.appendingPathComponent(".headroom-removing-5D1C2E0A")
        try FileManager.default.createDirectory(at: interrupted, withIntermediateDirectories: true)
        let halfDeleted = await worker.refresh(check: check(home: home), lookUpDesktopApp: { false }, now: Date())
        #expect(halfDeleted.bridgeState == .notInstalled)
        #expect(halfDeleted.hasBridgeLeftovers)

        try FileManager.default.removeItem(at: interrupted)
        try FileManager.default.createDirectory(at: claude.appendingPathComponent("headroom/sessions"), withIntermediateDirectories: true)
        let leftFolder = await worker.refresh(check: check(home: home), lookUpDesktopApp: { false }, now: Date())
        #expect(leftFolder.bridgeState == .notInstalled)
        #expect(leftFolder.hasBridgeLeftovers)

        // Disconnect deletes them.
        try await worker.uninstallBridge(claudeDirectory: claude)
        let afterDisconnect = await worker.refresh(check: check(home: home), lookUpDesktopApp: { false }, now: Date())
        #expect(!afterDisconnect.hasBridgeLeftovers)
    }

    /// A connected bridge's folder is its own, not a leftover; nor can anything be known about an
    /// unreadable `~/.claude`.
    @Test func onlyADisconnectedBridgeHasLeftovers() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let claude = ClaudePaths.standard(home: home).claudeDirectory
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try BridgeInstaller(claudeDirectory: claude).install()

        let connected = await SnapshotWorker().refresh(check: check(home: home), lookUpDesktopApp: { false }, now: Date())
        #expect(connected.bridgeState == .installed)
        #expect(!connected.hasBridgeLeftovers)

        let ungranted = await SnapshotWorker().refresh(check: check(home: home, claudeGranted: false), lookUpDesktopApp: { false }, now: Date())
        #expect(ungranted.bridgeState == nil)
        #expect(!ungranted.hasBridgeLeftovers)
    }

    /// A slow or hung mount under `~/.claude` must not freeze the pill and panel: the folders are
    /// probed, and the Claude app looked up, on the worker, never on the main thread.
    @MainActor
    @Test func accessIsProbedOffTheMainThread() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = ClaudePaths.standard(home: home)
        try FileManager.default.createDirectory(at: paths.claudeDirectory, withIntermediateDirectories: true)

        let lookedUpOnMain = OSAllocatedUnfairLock<Bool?>(initialState: nil)
        var due = check(home: home)
        due.desktopAppInstalled = nil
        let result = await SnapshotWorker().refresh(check: due, lookUpDesktopApp: {
            lookedUpOnMain.withLock { $0 = pthread_main_np() != 0 }
            return false
        }, now: Date())

        #expect(lookedUpOnMain.withLock { $0 } == false)
        #expect(result.access.state.claudeDirectoryReadable)
        #expect(result.access.lookedUpDesktopApp == false)
    }

    /// No `~/.claude` at all: nothing to grant, so no access issue (docs/app-store.md §7).
    @Test func withoutClaudeCodeTheSnapshotReportsNoFolderIssue() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let result = await SnapshotWorker().refresh(check: check(home: home, claudeGranted: false), lookUpDesktopApp: { false }, now: Date())
        #expect(!result.access.claudeCodeInstalled)
        #expect(result.snapshot.issues.isEmpty)
        #expect(result.bridgeState == nil)
    }

    @Test func anUngrantedClaudeFolderIsStillReported() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: ClaudePaths.standard(home: home).claudeDirectory, withIntermediateDirectories: true)

        let result = await SnapshotWorker().refresh(check: check(home: home, claudeGranted: false), lookUpDesktopApp: { false }, now: Date())
        #expect(result.access.claudeCodeInstalled)
        #expect(result.snapshot.issues == [.claudeCodeFolderUnavailable])
        #expect(result.bridgeState == nil)
    }

    /// The bridge state comes from `SnapshotBuilder`'s cache, re-checked only when settings.json
    /// or bridge.sh change stamp, not from parsing settings.json again on every 2 s poll.
    @Test func theBridgeStateIsTheBuildersCachedOne() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let claude = ClaudePaths.standard(home: home).claudeDirectory
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        let settings = claude.appendingPathComponent("settings.json")
        try Data(#"{"model":"opus"}"#.utf8).write(to: settings)

        let worker = SnapshotWorker()
        let first = await worker.refresh(check: check(home: home), lookUpDesktopApp: { false }, now: Date())
        #expect(first.bridgeState == .notInstalled)

        // Same size, same inode, same mtime: the builder's stamp can't see the change, a fresh parse can.
        try overwriteKeepingStamp(settings, with: Data(#"{"model":"opus"!"#.utf8))
        guard case .settingsUnreadable = BridgeInstaller(claudeDirectory: claude).state() else {
            Issue.record("an uncached check should see the invalid file")
            return
        }
        let second = await worker.refresh(check: check(home: home), lookUpDesktopApp: { false }, now: Date())
        #expect(second.bridgeState == .notInstalled)
        #expect(second.snapshot.terminalBridgeConnected == false)
    }

    private func overwriteKeepingStamp(_ url: URL, with data: Data) throws {
        var before = stat()
        guard stat(url.path, &before) == 0 else { throw CocoaError(.fileReadUnknown) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: data)
        try handle.close()
        var times = [before.st_atimespec, before.st_mtimespec]
        guard utimensat(AT_FDCWD, url.path, &times, 0) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
