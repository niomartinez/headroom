import Darwin

/// When the dropdown panel closes by itself (spec §1.2): a click outside, Esc, Headroom resigning
/// active, another app coming to the front, or the screen configuration changing.
enum PanelDismissal {
    /// Another regular app becoming active (Cmd-Tab, the Dock, a launch from Spotlight) closes the
    /// panel. Headroom itself becoming active (Settings, an alert) doesn't, and neither do agents
    /// without a Dock icon: on macOS 26 menu bar items belong to Control Center, which can activate
    /// around a click on the pill itself. Clicks are the click monitors' job. An activation that
    /// can't be identified closes the panel.
    static func closesOnActivation(of app: (pid: pid_t, isRegularApp: Bool)?, ownPID: pid_t) -> Bool {
        guard let app else { return true }
        return app.pid != ownPID && app.isRegularApp
    }
}
