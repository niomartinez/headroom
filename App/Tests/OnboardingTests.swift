import Foundation
import Testing

@Suite("First-run setup")
@MainActor
struct OnboardingTests {
    @Test func setupOnlyCompletesWhenFinishedOrSkipped() {
        let name = "HeadroomOnboardingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { UserDefaults().removePersistentDomain(forName: name) }
        Preferences.registerDefaults(in: defaults)
        let navigation = SettingsNavigation(defaults: defaults)
        #expect(!defaults.bool(forKey: Preferences.didShowOnboarding))
        navigation.beginOnboarding()
        #expect(navigation.isOnboarding)
        #expect(navigation.tab == .tools)
        #expect(!defaults.bool(forKey: Preferences.didShowOnboarding))
        // A relaunch before completion must still offer setup.
        #expect(!defaults.bool(forKey: Preferences.didShowOnboarding))
        navigation.finishOnboarding()
        #expect(!navigation.isOnboarding)
        #expect(defaults.bool(forKey: Preferences.didShowOnboarding))
        // Reopening setup does not reset the user's connections or tracking choices.
        defaults.set(true, forKey: Preferences.trackCopilot)
        navigation.beginOnboarding()
        #expect(defaults.bool(forKey: Preferences.trackCopilot))
        #expect(navigation.isOnboarding)
        navigation.finishOnboarding()
        #expect(SettingsNavigation(defaults: defaults).tab == .tools)
    }
}
