import Foundation
import Observation

/// The Settings window's selected tab (1.1 §6.4), remembered across launches: opening Settings from Applications
/// shows the tab last used; onboarding and Reconnect open a given tab.
@MainActor
@Observable
final class SettingsNavigation {
    private(set) var tab: SettingsTab
    private(set) var isOnboarding = false
    @ObservationIgnored private let defaults: UserDefaults

    var isFirstRun: Bool { !defaults.bool(forKey: Preferences.didShowOnboarding) }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        tab = SettingsTab(defaults: defaults)
    }

    func select(_ tab: SettingsTab) {
        guard tab != self.tab else { return }
        self.tab = tab
        defaults.set(tab.rawValue, forKey: Preferences.settingsTab)
    }

    func beginOnboarding() {
        select(.tools)
        isOnboarding = true
    }

    func finishOnboarding() {
        guard isOnboarding else { return }
        defaults.set(true, forKey: Preferences.didShowOnboarding)
        isOnboarding = false
    }
}
