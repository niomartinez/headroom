import Foundation
import HeadroomModel

/// The folders Headroom reads (spec §2, §4; 1.1 §3.1, §4.9). Sandboxed builds ask for each one once in an open panel
/// and keep the grant as a security-scoped bookmark (`bookmarkKey`).
enum HeadroomFolder: String, CaseIterable, Identifiable, Sendable {
    /// `~/.claude`: sessions, transcripts, and the terminal bridge (read-write).
    case claudeCode
    /// `~/Library/Application Support/Claude`: the Claude app's plan usage history (read only).
    case claudeApp
    /// `~/.codex`, or the folder the user set as `CODEX_HOME`: Codex's session files (read only, 1.1 §3.1).
    case codex
    /// `~/.copilot`, or the folder the user set as `COPILOT_HOME`: Connect Copilot CLI's hooks file and script, and the
    /// records that script writes (read-write, 1.1 §4.9). Asked for only when the user connects Copilot CLI.
    case copilotCLI

    /// Claude's two folders: Settings › Tools › Claude, and the Claude part of "Give access".
    static let claude: [HeadroomFolder] = [.claudeCode, .claudeApp]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeCode: "Claude Code folder"
        case .claudeApp: "Claude app folder"
        case .codex: "Codex folder"
        case .copilotCLI: "Copilot CLI folder"
        }
    }

    var displayPath: String {
        switch self {
        case .claudeCode: "~/.claude"
        case .claudeApp: "~/Library/Application Support/Claude"
        case .codex: "~/.codex"
        case .copilotCLI: "~/.copilot"
        }
    }

    var purpose: String {
        switch self {
        case .claudeCode: "Sessions, context usage and Connect terminal. Read and write."
        case .claudeApp: "Plan usage recorded by the Claude app. Read only."
        case .codex: "Limits and sessions from the Codex app and CLI. Read only."
        case .copilotCLI: "Copilot CLI sessions, through Connect Copilot CLI. Read and write."
        }
    }

    /// Bookmarked with `securityScopeAllowOnlyReadAccess`: Headroom never writes there.
    var isReadOnly: Bool { self == .claudeApp || self == .codex }

    /// Whether Headroom asks for this folder when it can't read it. The Claude app's folder only matters when the
    /// Claude desktop app is installed; terminal-only users never need it (spec §2.1). Likewise `~/.claude` only exists
    /// once Claude Code is installed: until then the open panel couldn't even enter it, and desktop-only users (or App
    /// Review) have nothing to grant. Codex's folder only once Codex is installed (1.1 §3.1). The Copilot CLI folder is
    /// asked for by Connect Copilot CLI only, never on its own.
    func isNeeded(desktopAppInstalled: Bool, claudeCodeInstalled: Bool = true, codexInstalled: Bool = true) -> Bool {
        switch self {
        case .claudeCode: claudeCodeInstalled
        case .claudeApp: desktopAppInstalled
        case .codex: codexInstalled
        case .copilotCLI: false
        }
    }

    /// Where the folder lives in the user's real home (not the sandbox container).
    var expectedURL: URL {
        switch self {
        case .claudeCode: ClaudePaths.standard().claudeDirectory
        case .claudeApp: ClaudePaths.standard().desktopSupportDirectory
        case .codex: CodexPaths.standard().codexDirectory
        case .copilotCLI: CopilotPaths.standard().copilotDirectory
        }
    }

    /// Subfolders that make a folder other than `expectedURL` acceptable: a sandboxed app can't read `CODEX_HOME` or
    /// `COPILOT_HOME`, so a folder that has what the tool keeps there is taken as the tool's home (1.1 §3.1, §4.9).
    /// Only their existence is checked. Claude's folders have a fixed place.
    var homeMarkers: [String] {
        switch self {
        case .claudeCode, .claudeApp: []
        case .codex: ["sessions"]
        case .copilotCLI: ["logs", "session-state"]
        }
    }

    var openPanelMessage: String {
        switch self {
        case .claudeCode:
            "Headroom reads your Claude Code sessions and context usage from the hidden “.claude” folder in your home folder. Connect terminal also adds its status line and hooks there. Click Grant Access to allow it."
        case .claudeApp:
            "Headroom reads your plan usage from the Claude app's folder (Library › Application Support › Claude). It only reads this folder. Click Grant Access to allow it."
        case .codex:
            "Headroom reads your Codex limits and sessions from the hidden “.codex” folder in your home folder. It only reads. Click Grant Access to allow it."
        case .copilotCLI:
            "Connect Copilot CLI adds a hooks file and a small script to the hidden “.copilot” folder in your home folder, and Headroom reads the session records that script writes there. Click Grant Access to allow it."
        }
    }

    /// The second half of "That's not the … folder": what Headroom takes instead.
    var wrongFolderMessage: String {
        switch self {
        case .claudeCode, .claudeApp:
            "Headroom needs \(displayPath) and asks for nothing else."
        case .codex:
            "Headroom needs \(displayPath), or the folder you set as CODEX_HOME (it has a “sessions” folder inside), and asks for nothing else."
        case .copilotCLI:
            "Headroom needs \(displayPath), or the folder you set as COPILOT_HOME, and asks for nothing else."
        }
    }

    /// Shown instead of the open panel when the folder doesn't exist yet: the panel could neither
    /// enter nor create it, and any other folder would be refused.
    var missingFolderMessage: String {
        switch self {
        case .claudeCode:
            "Claude Code creates \(displayPath) the first time it runs. Install Claude Code and run it once, then try again. Until then Headroom doesn't need this folder."
        case .claudeApp:
            "The Claude app creates this folder the first time it opens. Open the Claude app once, then try again."
        case .codex:
            "Codex creates \(displayPath) the first time it runs. Open the Codex app or run codex once, then try again. Until then Headroom doesn't need this folder."
        case .copilotCLI:
            "Copilot CLI creates \(displayPath) the first time it runs. Run copilot once, then try again."
        }
    }

    /// `folderBookmark.claudeCode`, `folderBookmark.claudeApp`, `folderBookmark.codex`, `folderBookmark.copilotCLI`.
    var bookmarkKey: String { "folderBookmark.\(rawValue)" }
}
