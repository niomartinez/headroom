import Foundation
import HeadroomModel
import Testing

/// The Codex and Copilot CLI folders (1.1 §3.1, §4.9): what a poll's access check finds, which folders an open panel
/// accepts, and how Settings shows the Codex folder.
@Suite struct ToolFolderAccessTests {
    private func makeHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeadroomToolFolderAccessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func check(
        home: URL, codexGranted: Bool = true, copilotGranted: Bool = true, codexAppInstalled: Bool? = false
    ) -> AccessCheck {
        let paths = ClaudePaths.standard(home: home)
        let codex = CodexPaths.standard(home: home).codexDirectory
        let copilot = CopilotPaths.standard(home: home).copilotDirectory
        return AccessCheck(
            paths: paths,
            claudeGranted: false,
            desktopGranted: false,
            claudeCodeLocation: paths.claudeDirectory,
            desktopAppInstalled: false,
            generation: 0,
            tools: AccessCheck.ToolFolders(
                codexDirectory: codex, codexGranted: codexGranted, codexLocation: codex,
                codexAppInstalled: codexAppInstalled,
                copilotDirectory: copilot, copilotGranted: copilotGranted, copilotLocation: copilot
            )
        )
    }

    // MARK: Access check

    @Test func withoutToolFoldersNothingAboutCodexOrCopilotIsProbed() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        var plain = check(home: home)
        plain.tools = nil
        var lookedUp = false
        let result = plain.run(lookUpDesktopApp: { false }, lookUpCodexApp: { lookedUp = true; return true })
        #expect(!lookedUp)
        #expect(!result.state.codexInstalled && !result.state.codexDirectoryReadable)
        #expect(!result.state.copilotCLIInstalled && !result.state.copilotDirectoryReadable)
    }

    @Test func aGrantedCodexFolderIsReadableAndMeansCodexIsInstalled() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: CodexPaths.standard(home: home).sessionsDirectory, withIntermediateDirectories: true)

        let result = check(home: home).run(lookUpDesktopApp: { false })
        #expect(result.state.codexDirectoryReadable)
        #expect(result.state.codexInstalled)
    }

    /// An existing `~/.codex` that isn't granted yet: installed (the offer shows), not readable.
    @Test func anUngrantedCodexFolderStillMeansInstalled() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: CodexPaths.standard(home: home).codexDirectory, withIntermediateDirectories: true)

        let result = check(home: home, codexGranted: false).run(lookUpDesktopApp: { false })
        #expect(!result.state.codexDirectoryReadable)
        #expect(result.state.codexInstalled)
    }

    /// No `~/.codex`, but the Codex app is installed (it creates the folder on first use).
    @Test func theCodexAppAloneMeansInstalled() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(!check(home: home, codexAppInstalled: false).run(lookUpDesktopApp: { false }).state.codexInstalled)
        #expect(check(home: home, codexAppInstalled: true).run(lookUpDesktopApp: { false }).state.codexInstalled)

        var lookups = 0
        let due = check(home: home, codexAppInstalled: nil).run(lookUpDesktopApp: { false }, lookUpCodexApp: {
            lookups += 1
            return true
        })
        #expect(lookups == 1)
        #expect(due.lookedUpCodexApp == true)
        #expect(due.state.codexInstalled)
    }

    @Test func theCopilotFolderIsProbedLikeCodex() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(!check(home: home).run(lookUpDesktopApp: { false }).state.copilotCLIInstalled)

        try FileManager.default.createDirectory(at: CopilotPaths.standard(home: home).logsDirectory, withIntermediateDirectories: true)
        let ungranted = check(home: home, copilotGranted: false).run(lookUpDesktopApp: { false })
        #expect(ungranted.state.copilotCLIInstalled)
        #expect(!ungranted.state.copilotDirectoryReadable)
        let granted = check(home: home).run(lookUpDesktopApp: { false })
        #expect(granted.state.copilotDirectoryReadable)
    }

    /// Codex tracked on a Mac without Codex: no "Give access" that could never succeed.
    @Test func codexFolderIssueIsDroppedWhileCodexIsNotInstalled() {
        var snapshot = HeadroomSnapshot.empty(at: Date())
        snapshot.issues = [.codexFolderUnavailable]
        var notInstalled = AccessCheck.Result(state: .none, claudeCodeInstalled: true, lookedUpDesktopApp: nil, generation: 0)
        #expect(notInstalled.adjusting(snapshot).issues.isEmpty)
        notInstalled.state.codexInstalled = true
        #expect(notInstalled.adjusting(snapshot).issues == [.codexFolderUnavailable])
    }

    // MARK: The open panel's choice

    @Test func codexAcceptsItsFolderOrACodexHome() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let codex = CodexPaths.standard(home: home).codexDirectory
        let custom = home.appendingPathComponent("codex-home", isDirectory: true)
        let other = home.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: custom.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        #expect(FolderGrant.isAcceptable(codex, for: .codex, expected: codex))
        #expect(FolderGrant.isAcceptable(custom, for: .codex, expected: codex))
        #expect(!FolderGrant.isAcceptable(other, for: .codex, expected: codex))
        // The parent of the real folder has no sessions/ of its own.
        #expect(!FolderGrant.isAcceptable(home, for: .codex, expected: codex))
    }

    @Test func claudesFoldersTakeNoSubstitute() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let lookalike = home.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: lookalike.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        let claude = ClaudePaths.standard(home: home).claudeDirectory
        #expect(!FolderGrant.isAcceptable(lookalike, for: .claudeCode, expected: claude))
    }

    @Test func copilotAcceptsACopilotHome() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let custom = home.appendingPathComponent("copilot-home", isDirectory: true)
        try FileManager.default.createDirectory(at: custom.appendingPathComponent("logs"), withIntermediateDirectories: true)
        let standard = CopilotPaths.standard(home: home).copilotDirectory
        #expect(FolderGrant.isAcceptable(custom, for: .copilotCLI, expected: standard))
        #expect(!FolderGrant.isAcceptable(home, for: .copilotCLI, expected: standard))
    }

    // MARK: Folders

    @Test func codexIsReadOnlyAndCopilotReadWrite() {
        #expect(HeadroomFolder.codex.isReadOnly)
        #expect(!HeadroomFolder.copilotCLI.isReadOnly)
        #expect(HeadroomFolder.codex.displayPath == "~/.codex")
        #expect(HeadroomFolder.codex.purpose == "Limits and sessions from the Codex app and CLI. Read only.")
        #expect(HeadroomFolder.codex.openPanelMessage == "Headroom reads your Codex limits and sessions from the hidden “.codex” folder in your home folder. It only reads. Click Grant Access to allow it.")
        #expect(HeadroomFolder.claude == [.claudeCode, .claudeApp])
    }

    /// Copilot CLI's folder is asked for by Connect Copilot CLI only, never by "Give access".
    @Test func onlyCodexAmongTheNewFoldersIsNeededOnItsOwn() {
        #expect(HeadroomFolder.codex.isNeeded(desktopAppInstalled: false, codexInstalled: true))
        #expect(!HeadroomFolder.codex.isNeeded(desktopAppInstalled: true, codexInstalled: false))
        #expect(!HeadroomFolder.copilotCLI.isNeeded(desktopAppInstalled: true, codexInstalled: true))
    }

    @Test func settingsNotesACodexFolderThatIsNotNeeded() {
        let missing = FolderAccessPresentation(
            folder: .codex, status: .notGranted, isSandboxed: true, desktopAppInstalled: false, codexInstalled: false
        )
        #expect(missing.note == FolderAccessPresentation.codexNotInstalledNote)
        #expect(!missing.showsGrantButton)

        let installed = FolderAccessPresentation(
            folder: .codex, status: .notGranted, isSandboxed: true, desktopAppInstalled: false, codexInstalled: true
        )
        #expect(installed.note == nil)
        #expect(installed.showsGrantButton)
    }
}
