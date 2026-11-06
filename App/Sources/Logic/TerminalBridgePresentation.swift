import SetupKit

/// How Settings describes the terminal bridge (spec §2.6) and which buttons it offers.
struct TerminalBridgePresentation: Equatable {
    enum Action: Equatable {
        case connect
        case update
        case disconnect
    }

    let status: String
    let actions: [Action]

    /// `state` is nil until the first check has run. Without `~/.claude` (Claude Code not
    /// installed) there is nothing to connect, and no folder to ask for. `hasLeftovers`
    /// (`SnapshotWorker.Result.hasBridgeLeftovers`): files a Disconnect couldn't delete are still
    /// there, so Disconnect stays available to delete them.
    init(state: BridgeInstallState?, claudeFolderReadable: Bool, claudeCodeInstalled: Bool = true, hasLeftovers: Bool = false) {
        guard claudeFolderReadable else {
            (status, actions) = (claudeCodeInstalled ? "Needs access to the .claude folder" : "Claude Code not found", [])
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
        case let .settingsUnreadable(reason):
            (status, actions) = ("Can't read ~/.claude/settings.json (\(reason))", [])
        }
    }
}
