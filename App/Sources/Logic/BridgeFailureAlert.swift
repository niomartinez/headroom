import Foundation
import SetupKit

/// The alerts Connect / Disconnect terminal show when they can't do their job (spec §2.6).
enum BridgeFailureAlert {
    static let connectTitle = "Headroom couldn't connect the terminal"
    static let disconnectTitle = "Headroom couldn't disconnect the terminal"

    /// The alert's text for a failed install or uninstall.
    static func message(for error: Error) -> String {
        switch error {
        case BridgeInstallError.settingsUnreadable(let reason):
            "~/.claude/settings.json couldn't be read (\(reason)). Nothing was changed. Fix or remove the file, then try again."
        case BridgeInstallError.settingsOutsideGrant:
            // The file is fine; the sandbox can't open where it links to. Never "fix or remove" it.
            error.localizedDescription
        case BridgeInstallError.writeFailed(let reason):
            reason
        default:
            error.localizedDescription
        }
    }

    /// Why Connect can't start in `state`, or nil when it can. Settings offers no button while
    /// settings.json can't be read, but the panel's gear menu always shows Connect terminal
    /// (HeadroomUI draws it), so that item explains instead of asking to change a file Headroom
    /// can't change. The reason may be a link outside the granted folder rather than a broken
    /// file, so this doesn't tell the user to fix anything.
    static func connectUnavailableMessage(for state: BridgeInstallState?) -> String? {
        guard case .settingsUnreadable(let reason) = state else { return nil }
        return "Headroom can't read ~/.claude/settings.json (\(reason)), so it can't add its status line and hooks. Nothing was changed."
    }
}
