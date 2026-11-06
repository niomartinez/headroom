/// Whether Headroom can read one of its folders right now.
enum FolderStatus: Equatable, Sendable {
    case readable
    /// Sandboxed and not granted yet.
    case notGranted
    /// Granted (or unsandboxed) but missing or unreadable, e.g. the Claude app isn't installed.
    case unavailable
}

/// How Settings › Tools shows one folder: a status label and a Grant access button, or, for a folder Headroom doesn't
/// need (its app isn't installed), a note in their place.
struct FolderAccessPresentation: Equatable {
    enum Tone: Equatable {
        case good
        case attention
        case neutral
    }

    struct Status: Equatable {
        let text: String
        /// SF Symbol name.
        let symbol: String
        let tone: Tone
    }

    static let desktopAppNotInstalledNote = "Claude desktop app not installed — not needed for terminal sessions"
    static let claudeCodeNotInstalledNote = "Claude Code not found — not needed until you install it"
    static let codexNotInstalledNote = "Codex not found — not needed until you install it"

    /// Nil when `note` replaces the status.
    let status: Status?
    let showsGrantButton: Bool
    let note: String?

    init(
        folder: HeadroomFolder, status: FolderStatus, isSandboxed: Bool, desktopAppInstalled: Bool,
        claudeCodeInstalled: Bool = true, codexInstalled: Bool = true
    ) {
        // A readable folder is shown as such even when the app is gone (a folder left behind).
        let needed = folder == .copilotCLI || folder.isNeeded(
            desktopAppInstalled: desktopAppInstalled, claudeCodeInstalled: claudeCodeInstalled, codexInstalled: codexInstalled
        )
        if status != .readable, !needed {
            self.status = nil
            showsGrantButton = false
            note = switch folder {
            case .claudeCode: Self.claudeCodeNotInstalledNote
            case .claudeApp: Self.desktopAppNotInstalledNote
            case .codex, .copilotCLI: Self.codexNotInstalledNote
            }
            return
        }
        self.status = switch status {
        case .readable: Status(text: isSandboxed ? "Granted" : "Readable", symbol: "checkmark.circle.fill", tone: .good)
        case .notGranted: Status(text: "Not granted", symbol: "exclamationmark.circle", tone: .attention)
        case .unavailable: Status(text: "Not found", symbol: "questionmark.circle", tone: .neutral)
        }
        showsGrantButton = isSandboxed && status != .readable
        note = nil
    }
}
