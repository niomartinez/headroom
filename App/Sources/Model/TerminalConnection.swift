import AppKit
import SetupKit

/// Connect / Disconnect terminal (spec §2.6). Connect always asks first, because it edits the
/// user's `~/.claude/settings.json`.
@MainActor
final class TerminalConnection {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    /// Also used for "Update" when an older bridge is installed: the changes are the same.
    func connect() {
        guard !model.isChangingBridge else { return }
        // Settings offers no Connect while settings.json can't be read; the panel's gear menu
        // still does, so explain instead of asking for a change that would fail.
        if let unavailable = BridgeFailureAlert.connectUnavailableMessage(for: model.bridgeState) {
            Self.showAlert(BridgeFailureAlert.connectTitle, message: unavailable)
            return
        }
        if !model.access.state.claudeDirectoryReadable {
            guard model.access.requestAccess(to: .claudeCode) else { return }
        }
        guard confirmConnect() else { return }
        Task {
            do {
                try await model.installBridge()
            } catch {
                Self.showAlert(BridgeFailureAlert.connectTitle, message: BridgeFailureAlert.message(for: error))
            }
        }
    }

    /// Also deletes files an earlier Disconnect left behind (`AppModel.hasBridgeLeftovers`).
    func disconnect() {
        guard !model.isChangingBridge else { return }
        Task {
            do {
                try await model.uninstallBridge()
                Self.showDisconnected()
            } catch {
                Self.showAlert(BridgeFailureAlert.disconnectTitle, message: BridgeFailureAlert.message(for: error))
            }
        }
    }

    /// Running sessions keep calling the deleted script until restarted; say so, once.
    private static func showDisconnected() {
        NSApplication.shared.activate()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = BridgeDisconnectNotice.title
        alert.informativeText = BridgeDisconnectNotice.message
        alert.runModal()
    }

    private func confirmConnect() -> Bool {
        NSApplication.shared.activate()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = BridgeConsent.title
        alert.informativeText = BridgeConsent.message
        alert.addButton(withTitle: BridgeConsent.confirmButton)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// The texts, including the one for `BridgeInstallError.settingsOutsideGrant`, are in
    /// `BridgeFailureAlert`.
    private static func showAlert(_ title: String, message: String) {
        NSApplication.shared.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
