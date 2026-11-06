#if HEADROOM_COPILOT_CLI
import AppKit

/// Connect / Disconnect Copilot CLI (1.1 §4.9, §6.4). Both ask first and list every change before anything is
/// written, because they write into the user's `~/.copilot`. Connect asks for the folder first when the sandbox hasn't
/// been given it.
@MainActor
final class CopilotCLIConnection {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    /// Also used for "Update" when an older script is installed: the changes are the same.
    func connect() {
        guard !model.isChangingCopilotCLI else { return }
        if model.access.status(of: .copilotCLI) != .readable {
            guard model.access.requestAccess(to: .copilotCLI) else { return }
        }
        Task {
            let changes = await model.copilotCLIPlan(uninstalling: false)
            guard Self.confirm(
                CopilotCLIConsent.connectTitle,
                message: CopilotCLIConsent.text(CopilotCLIConsent.connectMessage, changes: changes),
                button: CopilotCLIConsent.connectButton
            ) else { return }
            do {
                try await model.installCopilotCLI()
            } catch {
                Self.showAlert(CopilotCLIConsent.connectFailedTitle, message: error.localizedDescription)
            }
        }
    }

    /// Also deletes files an earlier Disconnect left behind (`AppModel.hasCopilotCLILeftovers`).
    func disconnect() {
        guard !model.isChangingCopilotCLI else { return }
        Task {
            let changes = await model.copilotCLIPlan(uninstalling: true)
            guard Self.confirm(
                CopilotCLIConsent.disconnectTitle,
                message: CopilotCLIConsent.text(CopilotCLIConsent.disconnectMessage, changes: changes),
                button: CopilotCLIConsent.disconnectButton
            ) else { return }
            do {
                try await model.uninstallCopilotCLI()
            } catch {
                Self.showAlert(CopilotCLIConsent.disconnectFailedTitle, message: error.localizedDescription)
            }
        }
    }

    private static func confirm(_ title: String, message: String, button: String) -> Bool {
        NSApplication.shared.activate()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func showAlert(_ title: String, message: String) {
        NSApplication.shared.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
#endif
