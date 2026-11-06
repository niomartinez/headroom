import Foundation

/// Whether "Connect sessions" is in place (1.1 §4.9), as the app shows it. SetupKit's `CopilotBridgeState` exists
/// only in builds with Copilot CLI support (`HEADROOM_COPILOT_CLI`); this one exists in every build.
enum CopilotCLIState: Sendable, Equatable {
    case notInstalled
    case installed
    /// Some of it is there but not current.
    case outdated
    /// The Copilot folder or the hooks file can't be read; the message says why.
    case unreadable(String)

    /// Installed, or installed with an older script that still reports: Copilot CLI sessions are read.
    var isConnected: Bool { self == .installed || self == .outdated }
}

/// How Settings › Tools › GitHub Copilot describes Connect sessions, and which buttons it offers (1.1 §6.4).
struct CopilotCLIPresentation: Equatable {
    enum Action: Equatable {
        case connect
        case update
        case disconnect
    }

    let status: String
    let actions: [Action]

    /// `state` is nil until a check has run on a readable folder. `granted`: sandboxed builds need the folder granted
    /// first; Connect asks for it. `installed`: `~/.copilot` exists (Copilot CLI has run). `hasLeftovers`: files a
    /// Disconnect couldn't delete are still there, so Disconnect stays available to delete them.
    init(state: CopilotCLIState?, granted: Bool, folderReadable: Bool, installed: Bool, hasLeftovers: Bool = false) {
        guard folderReadable else {
            if !installed {
                (status, actions) = ("Start Copilot once, then connect here", [])
            } else if granted {
                (status, actions) = ("Can't read the ~/.copilot folder", [.connect])
            } else {
                (status, actions) = ("Not connected", [.connect])
            }
            return
        }
        switch state {
        case nil:
            (status, actions) = ("Checking…", [])
        case .notInstalled where hasLeftovers:
            (status, actions) = ("Not connected (files left from an earlier connection)", [.connect, .disconnect])
        case .notInstalled:
            (status, actions) = ("Not connected", [.connect])
        case .installed:
            (status, actions) = ("Connected", [.disconnect])
        case .outdated:
            (status, actions) = ("Connected, update available", [.update, .disconnect])
        case let .unreadable(reason):
            (status, actions) = (reason, [])
        }
    }

    static func title(for action: Action) -> String {
        switch action {
        case .connect: "Connect sessions…"
        case .update: "Update…"
        case .disconnect: "Disconnect"
        }
    }
}

/// The dialogs around Connect and Disconnect Copilot sessions (1.1 §4.9, §6.4). Each lists every change before anything
/// is written, from `CopilotBridgeInstaller`'s plans.
enum CopilotCLIConsent {
    static let connectTitle = "Connect sessions?"
    static let connectMessage = "Headroom will add ~/.copilot/hooks/headroom.json and a small script in ~/.copilot/headroom. The Copilot desktop app and CLI then tell Headroom when a session starts, works, needs you or ends. Only session ids, folder paths and event names are recorded, never prompts. Disconnect removes both. New hooks apply to sessions started after connecting."
    static let connectButton = "Connect"

    static let disconnectTitle = "Disconnect Copilot sessions?"
    static let disconnectMessage = "Headroom will stop showing Copilot sessions. Sessions that are already running keep calling the hooks until they end, which is harmless: the hooks skip the removed script."
    static let disconnectButton = "Disconnect"

    static let connectFailedTitle = "Headroom couldn't connect Copilot sessions"
    static let disconnectFailedTitle = "Headroom couldn't disconnect Copilot sessions"

    /// A change as the dialog lists it: `path`, `verb` (Create, Replace, Remove) and `detail`.
    struct Change: Equatable, Sendable {
        var verb: String
        var path: String
        var detail: String
    }

    /// `message` followed by the list of changes, one bullet each.
    static func text(_ message: String, changes: [Change]) -> String {
        guard !changes.isEmpty else { return message }
        let lines = changes.map { "• \($0.verb) \($0.path): \($0.detail)" }
        return message + "\n\n" + lines.joined(separator: "\n")
    }
}
