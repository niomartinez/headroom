import Foundation
import HeadroomModel
import HeadroomUI
import Testing

/// The per-poll access check (spec §4): which granted folders are readable, and whether Claude Code
/// is installed at all, told apart from "installed but not granted" without a grant.
@Suite struct AccessCheckTests {
    private func makeHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeadroomAccessCheckTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func check(
        home: URL, claudeGranted: Bool = true, desktopGranted: Bool = true,
        desktopAppInstalled: Bool? = true, generation: Int = 0
    ) -> AccessCheck {
        let paths = ClaudePaths.standard(home: home)
        return AccessCheck(
            paths: paths,
            claudeGranted: claudeGranted,
            desktopGranted: desktopGranted,
            claudeCodeLocation: paths.claudeDirectory,
            desktopAppInstalled: desktopAppInstalled,
            generation: generation
        )
    }

    // MARK: Missing vs. present

    @Test func aFolderThatDoesNotExistIsMissing() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(AccessProbe.isMissing(home.appendingPathComponent(".claude", isDirectory: true)))
    }

    @Test func anExistingFolderIsNotMissing() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(!AccessProbe.isMissing(home))
    }

    /// Only "no such file" means missing. A folder the process may not look into (the sandbox's
    /// EPERM, or EACCES here) is present, so the user is still asked for it.
    @Test func aFolderThatCannotBeExaminedIsNotMissing() throws {
        let home = try makeHome()
        let locked = home.appendingPathComponent("locked", isDirectory: true)
        let inside = locked.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: home)
        }
        #expect(!AccessProbe.isMissing(inside))
    }

    @Test func aSymlinkToNothingIsMissing() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let link = home.appendingPathComponent(".claude")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: home.appendingPathComponent("gone"))
        #expect(AccessProbe.isMissing(link))
    }

    // MARK: Running a check

    @Test func grantedExistingFoldersAreReadable() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = ClaudePaths.standard(home: home)
        try FileManager.default.createDirectory(at: paths.claudeDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.desktopSupportDirectory, withIntermediateDirectories: true)

        let result = check(home: home).run { true }
        #expect(result.state == AccessState(claudeDirectoryReadable: true, desktopDirectoryReadable: true, desktopAppInstalled: true))
        #expect(result.claudeCodeInstalled)
    }

    @Test func foldersThatArentGrantedAreNotReadableEvenWhenTheyExist() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = ClaudePaths.standard(home: home)
        try FileManager.default.createDirectory(at: paths.claudeDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.desktopSupportDirectory, withIntermediateDirectories: true)

        let result = check(home: home, claudeGranted: false, desktopGranted: false).run { true }
        #expect(!result.state.claudeDirectoryReadable)
        #expect(!result.state.desktopDirectoryReadable)
        #expect(result.claudeCodeInstalled)
    }

    @Test func withoutTheClaudeFolderClaudeCodeIsNotInstalled() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let result = check(home: home, claudeGranted: false).run { true }
        #expect(!result.claudeCodeInstalled)
        #expect(!result.state.claudeDirectoryReadable)
    }

    @Test func aCachedDesktopAppAnswerIsNotLookedUpAgain() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        var lookups = 0
        let result = check(home: home, desktopAppInstalled: false).run { lookups += 1; return true }
        #expect(lookups == 0)
        #expect(!result.state.desktopAppInstalled)
        #expect(result.lookedUpDesktopApp == nil)
    }

    @Test func aDueDesktopAppAnswerIsLookedUpOnce() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        var lookups = 0
        let result = check(home: home, desktopAppInstalled: nil, generation: 7).run { lookups += 1; return true }
        #expect(lookups == 1)
        #expect(result.state.desktopAppInstalled)
        #expect(result.lookedUpDesktopApp == true)
        #expect(result.generation == 7)
    }

    // MARK: What the snapshot reports

    private func snapshot(issues: Set<DataIssue>) -> HeadroomSnapshot {
        HeadroomSnapshot(plan: .empty, sessions: [], terminalBridgeConnected: false, issues: issues, generatedAt: Date())
    }

    private func result(claudeCodeInstalled: Bool) -> AccessCheck.Result {
        AccessCheck.Result(
            state: AccessState(claudeDirectoryReadable: false, desktopDirectoryReadable: false, desktopAppInstalled: false),
            claudeCodeInstalled: claudeCodeInstalled,
            lookedUpDesktopApp: nil,
            generation: 0
        )
    }

    /// No `~/.claude` (App Review's Mac, desktop-only users): there is nothing to grant, so the panel
    /// shows its empty state instead of an access prompt that can never succeed (docs/app-store.md §7).
    @Test func withoutClaudeCodeThePanelShowsItsEmptyState() {
        let adjusted = result(claudeCodeInstalled: false).adjusting(snapshot(issues: [.claudeCodeFolderUnavailable]))
        #expect(!adjusted.issues.contains(.claudeCodeFolderUnavailable))
        let panel = PanelModel(snapshot: adjusted, now: Date())
        #expect(panel.accessMessage == nil)
        #expect(panel.emptyMessage == "No Claude Code sessions running")
    }

    @Test func withClaudeCodeInstalledMissingAccessIsStillReported() {
        let adjusted = result(claudeCodeInstalled: true).adjusting(snapshot(issues: [.claudeCodeFolderUnavailable]))
        #expect(adjusted.issues == [.claudeCodeFolderUnavailable])
        #expect(PanelModel(snapshot: adjusted, now: Date()).accessMessage == "Headroom needs access to ~/.claude to see sessions.")
    }

    @Test func withoutClaudeCodeTheDesktopFolderIsStillAskedFor() {
        let adjusted = result(claudeCodeInstalled: false)
            .adjusting(snapshot(issues: [.claudeCodeFolderUnavailable, .desktopFolderUnavailable]))
        #expect(adjusted.issues == [.desktopFolderUnavailable])
        #expect(PanelModel(snapshot: adjusted, now: Date()).accessMessage == "Headroom needs access to the Claude app's folder to read limits.")
    }
}
