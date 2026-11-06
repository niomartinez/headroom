import Foundation

/// UserDefaults keys the app owns. The 1.0 keys keep their names and defaults (1.1 §0.1).
enum Preferences {
    static let showMoments = "showMoments"
    static let didShowOnboarding = "didShowOnboarding"
    /// Sample data mode (`SampleDataMode`): off unless the user turns it on.
    static let showSampleData = "showSampleData"

    // 1.1 §6.4

    /// "Rings show": `RingsChoice` raw values, "automatic" by default.
    static let ringsTool = "ringsTool"
    /// "One gauge per tool".
    static let gaugePerTool = "gaugePerTool"
    static let menuBarLayout = "menuBarLayout"
    static let trackClaude = "trackClaude"
    /// Absent until the user decides (the panel offers Codex meanwhile, 1.1 §6.3), so never registered.
    static let trackCodex = "trackCodex"
    static let trackCopilot = "trackCopilot"
    /// `CopilotPlan` raw values, "notSure" by default.
    static let copilotPlan = "copilotPlan"
    /// Settings › Copilot › Plan › Custom: a number, 1–1,000,000.
    static let copilotCustomAllowance = "copilotCustomAllowance"
    /// The connected GitHub login, for display only; the tokens live in the Keychain (1.1 §4.3).
    static let copilotLogin = "copilotLogin"
    static let widgetShowsSessionNames = "widgetShowsSessionNames"
    /// The Settings tab last shown (`SettingsTab` raw values).
    static let settingsTab = "settingsTab"

    // 1.1 §14.4

    /// "Keep “needs you” in the menu bar until I look", on by default.
    static let keepNeedsYou = "keepNeedsYou"
    /// Waiting episodes the user saw (`NeedsYouTracker.seen`), as `NeedsYouMarks` arrays.
    static let needsYouAcknowledged = "needsYouAcknowledged"
    /// Waiting episodes the user dismissed (`NeedsYouTracker.dismissed`), as `NeedsYouMarks` arrays.
    static let needsYouDismissed = "needsYouDismissed"
    /// Just finished (1.1.1): session id → when it finished, in seconds since 1970. Only ids and times.
    static let justFinished = "justFinished"

    static func registerDefaults(in defaults: UserDefaults) {
        defaults.register(defaults: [
            showMoments: true,
            showSampleData: false,
            ringsTool: RingsChoice.automatic.rawValue,
            gaugePerTool: false,
            menuBarLayout: MenuBarLayout.automatic.rawValue,
            trackClaude: true,
            trackCopilot: false,
            copilotPlan: "notSure",
            widgetShowsSessionNames: true,
            keepNeedsYou: true,
        ])
    }
}
