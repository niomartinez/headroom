import AppKit
import HeadroomUI

/// Builds the app's parts and wires them together: model, pill, panel, Settings (spec §4).
@MainActor
final class AppCoordinator {
    private let defaults: UserDefaults
    private let access: AccessManager
    private let model: AppModel
    private let settings: SettingsWindowController
    private let panel: PanelController
    private let statusItem: StatusItemController
    private var wakeObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        Preferences.registerDefaults(in: defaults)
        let access = AccessManager(defaults: defaults)
        let model = AppModel(access: access, defaults: defaults)
        let terminal = TerminalConnection(model: model)
        #if HEADROOM_COPILOT_CLI
        let connection = CopilotCLIConnection(model: model)
        let copilotCLI: CopilotCLIActions? = CopilotCLIActions(
            connect: { connection.connect() }, disconnect: { connection.disconnect() }
        )
        #else
        let copilotCLI: CopilotCLIActions? = nil
        #endif
        let launchAtLogin = LaunchAtLogin()

        let grant: (HeadroomFolder?) -> Void = { folder in
            if let folder {
                if access.requestAccess(to: folder), folder == .codex {
                    model.codexAccessGranted()
                }
            } else {
                access.requestMissingAccess(tracking: model.tracking)
            }
            Task { await model.refresh() }
        }
        let navigation = SettingsNavigation(defaults: defaults)
        let settings = SettingsWindowController(
            launchAtLogin: launchAtLogin,
            navigation: navigation,
            // The Claude and Codex apps may have been installed or removed since the last look.
            onBecomeKey: { access.refresh(recheckDesktopApp: true) }
        ) { closeSettings in
            SettingsView(
                model: model, launchAtLogin: launchAtLogin, terminal: terminal, copilotCLI: copilotCLI,
                navigation: navigation, grantAccess: { grant($0) }, close: closeSettings
            )
        }
        let opener = SessionOpener(model: model)
        model.hostBundleID = { [weak opener] in opener?.hostBundleID(for: $0) }
        let panel = PanelController(model: model, actions: PanelActions(
            openSettings: { settings.show() },
            openToolsSettings: { settings.show(tab: .tools) },
            connectTerminal: { terminal.connect() },
            disconnectTerminal: { terminal.disconnect() },
            // Unsandboxed builds have nothing to grant; Settings shows which folder is missing.
            grantAccess: { access.isSandboxed ? grant(nil) : settings.show(tab: .tools) },
            refresh: { model.refreshNow() },
            quit: { NSApplication.shared.terminate(nil) },
            showSampleData: { model.setShowSampleData(true) },
            hideSampleData: { model.setShowSampleData(false) },
            giveCodexAccess: { model.giveCodexAccess() },
            declineCodex: { model.setTrackCodex(false) },
            reconnectGitHub: {
                settings.show(tab: .tools)
                model.copilot.beginSignIn()
            },
            // Click a session to open it (1.1 §14.3).
            sessionOpenTitle: { opener.title(for: $0) },
            // Opening a just-finished session from here reviews it (1.1.1).
            openSession: {
                model.reviewFinished($0)
                opener.open(id: $0)
            },
            // "Needs you" stays until seen (1.1 §14.4); "Just finished" until reviewed (1.1.1).
            dismissSession: { model.dismissSession($0) },
            undoDismiss: { model.undoDismissNeedsYou($0) },
            clearFinished: { model.clearFinished() }
        ))
        let statusItem = StatusItemController(model: model)
        statusItem.onClick = { [weak panel] button in panel?.toggle(from: button) }
        panel.onVisibilityChange = { [weak statusItem] shown in
            statusItem?.setHighlighted(shown)
            if !shown { opener.reset() }
        }

        self.defaults = defaults
        self.access = access
        self.model = model
        self.settings = settings
        self.panel = panel
        self.statusItem = statusItem
    }

    func start() {
        access.activate()
        model.start()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.didWake() }
        }
        if !defaults.bool(forKey: Preferences.didShowOnboarding) {
            settings.showOnboarding()
        }
    }

    func showSettings() {
        panel.close()
        settings.show()
    }

    /// `com.niomartinez.headroom://panel`, from a widget (1.1 §5.6): the panel under the pill, or Settings when the
    /// pill isn't on screen. Other URLs are ignored.
    func open(_ url: URL) {
        switch AppURL.action(for: url) {
        case .openPanel?:
            if let button = statusItem.visibleButton {
                if !panel.isVisible { panel.show(from: button) }
            } else {
                settings.show()
            }
        case nil:
            break
        }
    }

    func stop() {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        model.stop()
    }
}
