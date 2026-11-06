import Foundation
import HeadroomModel
import HeadroomSamples
import HeadroomUI
import Testing

/// The 1.1 preferences (§6.4): their defaults, "Rings show", the tracked tools and the Codex offer.
@Suite struct ToolSettingsTests {
    /// A fresh defaults domain with the app's defaults registered; removed by the caller.
    private func makeDefaults() -> (UserDefaults, String) {
        let name = "HeadroomToolSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        Preferences.registerDefaults(in: defaults)
        return (defaults, name)
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Defaults

    @Test func theNewPreferencesStartAsTheSpecSays() {
        let (defaults, name) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }

        #expect(defaults.string(forKey: Preferences.ringsTool) == "automatic")
        #expect(!defaults.bool(forKey: Preferences.gaugePerTool))
        #expect(defaults.bool(forKey: Preferences.trackClaude))
        #expect(!defaults.bool(forKey: Preferences.trackCopilot))
        #expect(defaults.string(forKey: Preferences.copilotPlan) == "notSure")
        #expect(defaults.bool(forKey: Preferences.widgetShowsSessionNames))
        // Undecided until the user answers the offer or flips the toggle.
        #expect(defaults.object(forKey: Preferences.trackCodex) == nil)
        #expect(defaults.object(forKey: Preferences.copilotLogin) == nil)
        #expect(defaults.object(forKey: Preferences.copilotCustomAllowance) == nil)
        // 1.0's, unchanged.
        #expect(defaults.bool(forKey: Preferences.showMoments))
        #expect(!defaults.bool(forKey: Preferences.showSampleData))
    }

    @Test func theKeysKeepTheirSpecNames() {
        #expect(Preferences.ringsTool == "ringsTool")
        #expect(Preferences.gaugePerTool == "gaugePerTool")
        #expect(Preferences.trackClaude == "trackClaude")
        #expect(Preferences.trackCodex == "trackCodex")
        #expect(Preferences.trackCopilot == "trackCopilot")
        #expect(Preferences.copilotPlan == "copilotPlan")
        #expect(Preferences.copilotCustomAllowance == "copilotCustomAllowance")
        #expect(Preferences.copilotLogin == "copilotLogin")
        #expect(Preferences.widgetShowsSessionNames == "widgetShowsSessionNames")
        #expect(Preferences.settingsTab == "settingsTab")
        #expect(HeadroomFolder.codex.bookmarkKey == "folderBookmark.codex")
        #expect(HeadroomFolder.copilotCLI.bookmarkKey == "folderBookmark.copilotCLI")
        // 1.0's bookmark keys are unchanged.
        #expect(HeadroomFolder.claudeCode.bookmarkKey == "folderBookmark.claudeCode")
        #expect(HeadroomFolder.claudeApp.bookmarkKey == "folderBookmark.claudeApp")
    }

    // MARK: Tracking

    @Test func anUpgradingClaudeUserTracksOnlyClaude() {
        let (defaults, name) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let tracking = ToolTracking(defaults: defaults)
        #expect(tracking == .claudeOnly)
        #expect(tracking.codex == nil)
        #expect(!tracking.tracksCodex)
    }

    @Test func trackCodexReadsYesNoAndUndecided() {
        let (defaults, name) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        defaults.set(true, forKey: Preferences.trackCodex)
        #expect(ToolTracking(defaults: defaults).codex == true)
        defaults.set(false, forKey: Preferences.trackCodex)
        #expect(ToolTracking(defaults: defaults).codex == false)
        defaults.removeObject(forKey: Preferences.trackCodex)
        #expect(ToolTracking(defaults: defaults).codex == nil)
    }

    // MARK: Rings show

    @Test func ringsShowMapsToTheToolItNames() {
        #expect(RingsChoice.automatic.tool == nil)
        #expect(RingsChoice.claude.tool == .claude)
        #expect(RingsChoice.codex.tool == .codex)
        #expect(RingsChoice.copilot.tool == .copilot)
        for choice in RingsChoice.allCases {
            #expect(RingsChoice(tool: choice.tool) == choice)
        }
        #expect(RingsChoice.allCases.map(\.title) == ["Automatic", "Claude", "Codex", "Copilot"])
    }

    @Test func anUnknownSavedChoiceReadsAsAutomatic() {
        let (defaults, name) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        defaults.set("gemini", forKey: Preferences.ringsTool)
        #expect(RingsChoice(defaults: defaults) == .automatic)
        defaults.set("codex", forKey: Preferences.ringsTool)
        #expect(RingsChoice(defaults: defaults) == .codex)
    }

    /// Only tracked tools with limits can be picked; Automatic always can.
    @Test func ringsShowOffersTrackedToolsWithLimits() {
        let sample = SampleData(now: now)
        let claudeOnly = sample.claudeOnlyShowcase(terminalConnected: true)
        #expect(RingsChoice.automatic.isAvailable(in: claudeOnly))
        #expect(RingsChoice.claude.isAvailable(in: claudeOnly))
        #expect(!RingsChoice.codex.isAvailable(in: claudeOnly))
        #expect(!RingsChoice.copilot.isAvailable(in: claudeOnly))

        let all = sample.multiTool
        #expect(RingsChoice.allCases.allSatisfy { $0.isAvailable(in: all) })

        // Tracked, but no limits yet.
        var codexWithout = claudeOnly
        codexWithout.codex = ToolUsage(tool: .codex, status: .noActivity)
        #expect(!RingsChoice.codex.isAvailable(in: codexWithout))
    }

    /// A pick that isn't tracked any more falls back to Automatic where it's used; the choice itself is kept.
    @Test func anUntrackedPickFallsBackToAutomatic() {
        let sample = SampleData(now: now)
        let claudeOnly = sample.claudeOnlyShowcase(terminalConnected: true)
        #expect(RingsTool.resolve(RingsChoice.codex.tool, in: claudeOnly) == .claude)
        #expect(RingsTool.resolve(RingsChoice.codex.tool, in: sample.multiTool) == .codex)
        #expect(RingsTool.resolve(RingsChoice.automatic.tool, in: sample.multiTool) == .claude)
    }

    @Test func oneGaugePerToolNeedsTwoTrackedTools() {
        let sample = SampleData(now: now)
        #expect(!GaugePerTool.isAvailable(in: sample.claudeOnlyShowcase(terminalConnected: true)))
        #expect(GaugePerTool.isAvailable(in: sample.multiTool))
        #expect(!GaugePerTool.isAvailable(in: sample.withoutClaude(codex: sample.codex())))
    }

    // MARK: Codex offer (1.1 §6.3)

    @Test func codexIsOfferedWhileUndecidedInstalledAndReal() {
        let undecided = ToolTracking.claudeOnly
        #expect(CodexOffer.shows(tracking: undecided, codexInstalled: true, sampleData: false))
        #expect(!CodexOffer.shows(tracking: undecided, codexInstalled: false, sampleData: false))
        #expect(!CodexOffer.shows(tracking: undecided, codexInstalled: true, sampleData: true))

        var yes = undecided
        yes.codex = true
        #expect(!CodexOffer.shows(tracking: yes, codexInstalled: true, sampleData: false))
        var no = undecided
        no.codex = false
        #expect(!CodexOffer.shows(tracking: no, codexInstalled: true, sampleData: false))
    }

    // MARK: Settings tab

    @Test func menuBarLayoutPersistsAndUnknownChoicesStayAutomatic() {
        let (defaults, name) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        #expect(MenuBarLayout(defaults: defaults) == .automatic)
        defaults.set(MenuBarLayout.compact.rawValue, forKey: Preferences.menuBarLayout)
        #expect(MenuBarLayout(defaults: defaults) == .compact)
        defaults.set("unknown", forKey: Preferences.menuBarLayout)
        #expect(MenuBarLayout(defaults: defaults) == .automatic)
    }

    @Test func settingsReopensOnTheLastTab() {
        let (defaults, name) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        #expect(SettingsTab(defaults: defaults) == .general)
        defaults.set(SettingsTab.tools.rawValue, forKey: Preferences.settingsTab)
        #expect(SettingsTab(defaults: defaults) == .tools)
        defaults.set("advanced", forKey: Preferences.settingsTab)
        #expect(SettingsTab(defaults: defaults) == .general)
    }
}
