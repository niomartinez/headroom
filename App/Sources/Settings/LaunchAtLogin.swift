import Observation
import ServiceManagement

/// Launch at login through `SMAppService.mainApp` (spec §1.3). The user can also change it in
/// System Settings, so `refresh()` re-reads the status whenever the Settings window becomes key.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    private(set) var errorMessage: String?

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    /// Registered, but the user still has to allow it in System Settings › General › Login Items.
    var needsApproval: Bool { status == .requiresApproval }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
