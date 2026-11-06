import Testing

@Suite struct FolderAccessPresentationTests {
    @Test func desktopFolderWithoutTheDesktopAppIsNotNeeded() {
        let presentation = FolderAccessPresentation(
            folder: .claudeApp, status: .notGranted, isSandboxed: true, desktopAppInstalled: false
        )
        #expect(presentation.note == "Claude desktop app not installed — not needed for terminal sessions")
        #expect(presentation.status == nil)
        #expect(!presentation.showsGrantButton)
    }

    @Test func missingDesktopFolderWithoutTheDesktopAppIsNotNeededInDevelopmentBuilds() {
        let presentation = FolderAccessPresentation(
            folder: .claudeApp, status: .unavailable, isSandboxed: false, desktopAppInstalled: false
        )
        #expect(presentation.note == FolderAccessPresentation.desktopAppNotInstalledNote)
        #expect(presentation.status == nil)
        #expect(!presentation.showsGrantButton)
    }

    @Test func desktopFolderWithTheDesktopAppInstalledOffersGrant() {
        let presentation = FolderAccessPresentation(
            folder: .claudeApp, status: .notGranted, isSandboxed: true, desktopAppInstalled: true
        )
        #expect(presentation.note == nil)
        #expect(presentation.status == .init(text: "Not granted", symbol: "exclamationmark.circle", tone: .attention))
        #expect(presentation.showsGrantButton)
    }

    /// A folder left behind after the app was removed still reads normally.
    @Test func readableDesktopFolderShowsAsGrantedEvenWithoutTheApp() {
        let presentation = FolderAccessPresentation(
            folder: .claudeApp, status: .readable, isSandboxed: true, desktopAppInstalled: false
        )
        #expect(presentation.note == nil)
        #expect(presentation.status == .init(text: "Granted", symbol: "checkmark.circle.fill", tone: .good))
        #expect(!presentation.showsGrantButton)
    }

    @Test func claudeCodeFolderDoesNotDependOnTheDesktopApp() {
        let presentation = FolderAccessPresentation(
            folder: .claudeCode, status: .notGranted, isSandboxed: true, desktopAppInstalled: false
        )
        #expect(presentation.note == nil)
        #expect(presentation.showsGrantButton)
    }

    @Test func developmentBuildsNeverOfferGrant() {
        let readable = FolderAccessPresentation(folder: .claudeCode, status: .readable, isSandboxed: false, desktopAppInstalled: true)
        #expect(readable.status == .init(text: "Readable", symbol: "checkmark.circle.fill", tone: .good))
        #expect(!readable.showsGrantButton)

        let missing = FolderAccessPresentation(folder: .claudeApp, status: .unavailable, isSandboxed: false, desktopAppInstalled: true)
        #expect(missing.status == .init(text: "Not found", symbol: "questionmark.circle", tone: .neutral))
        #expect(!missing.showsGrantButton)
    }

    @Test func grantedButUnreadableFolderCanBeGrantedAgain() {
        let presentation = FolderAccessPresentation(folder: .claudeCode, status: .unavailable, isSandboxed: true, desktopAppInstalled: true)
        #expect(presentation.status?.text == "Not found")
        #expect(presentation.showsGrantButton)
    }

    /// No `~/.claude` (App Review's Mac, desktop-only users): the open panel couldn't enter or create
    /// it, so Settings shows a note instead of a Grant access button that can never succeed.
    @Test func claudeCodeFolderWithoutClaudeCodeIsNotNeeded() {
        let presentation = FolderAccessPresentation(
            folder: .claudeCode, status: .notGranted, isSandboxed: true, desktopAppInstalled: true, claudeCodeInstalled: false
        )
        #expect(presentation.note == "Claude Code not found — not needed until you install it")
        #expect(presentation.note == FolderAccessPresentation.claudeCodeNotInstalledNote)
        #expect(presentation.status == nil)
        #expect(!presentation.showsGrantButton)
    }

    @Test func missingClaudeCodeFolderInDevelopmentBuildsShowsTheNote() {
        let presentation = FolderAccessPresentation(
            folder: .claudeCode, status: .unavailable, isSandboxed: false, desktopAppInstalled: false, claudeCodeInstalled: false
        )
        #expect(presentation.note == FolderAccessPresentation.claudeCodeNotInstalledNote)
        #expect(!presentation.showsGrantButton)
    }

    /// Claude Code missing says nothing about the Claude app's folder, and the other way round.
    @Test func eachFolderGetsItsOwnNote() {
        let desktop = FolderAccessPresentation(
            folder: .claudeApp, status: .notGranted, isSandboxed: true, desktopAppInstalled: false, claudeCodeInstalled: false
        )
        #expect(desktop.note == FolderAccessPresentation.desktopAppNotInstalledNote)
        let desktopNeeded = FolderAccessPresentation(
            folder: .claudeApp, status: .notGranted, isSandboxed: true, desktopAppInstalled: true, claudeCodeInstalled: false
        )
        #expect(desktopNeeded.note == nil)
        #expect(desktopNeeded.showsGrantButton)
    }

    @Test func claudeCodeFolderIsNeededOnlyWithClaudeCode() {
        #expect(!HeadroomFolder.claudeCode.isNeeded(desktopAppInstalled: true, claudeCodeInstalled: false))
        #expect(HeadroomFolder.claudeCode.isNeeded(desktopAppInstalled: false, claudeCodeInstalled: true))
        #expect(HeadroomFolder.claudeApp.isNeeded(desktopAppInstalled: true, claudeCodeInstalled: false))
        #expect(!HeadroomFolder.claudeApp.isNeeded(desktopAppInstalled: false, claudeCodeInstalled: true))
    }

    @Test func onlyTheClaudeCodeFolderIsNeededWithoutTheDesktopApp() {
        #expect(HeadroomFolder.claudeCode.isNeeded(desktopAppInstalled: false))
        #expect(!HeadroomFolder.claudeApp.isNeeded(desktopAppInstalled: false))
        #expect(HeadroomFolder.claudeCode.isNeeded(desktopAppInstalled: true))
        #expect(HeadroomFolder.claudeApp.isNeeded(desktopAppInstalled: true))
    }
}
