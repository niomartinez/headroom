/// Settings text worth pinning down in tests (1.1 §6.4, with §14.7's wording: AI usage, not just coding). "Pill" is
/// the design's word for the menu bar item; the user never sees it.
enum SettingsCopy {
    static let intro = "Headroom shows your AI usage and plan limits, and your running Claude Code, Codex and Copilot sessions, in the menu bar."
    static let showMomentsDetail = "Briefly show a message in the menu bar when a session finishes or needs you, or a limit passes 90%."
    /// Under Show moments (1.1 §14.4): after "harbor needs you", the menu bar keeps "(!) harbor" until the panel is
    /// opened.
    static let keepNeedsYou = "Keep “needs you” in the menu bar until I look"
    static let sampleDataDetail = "Fills the menu bar and panel with made-up sessions and limits, to see how Headroom works. Your own sessions and limits don't show while it's on."

    // General › Menu bar
    static let ringsShow = "Rings show"
    static let ringsShowCaption = "Automatic uses Claude, then Codex, then Copilot: the first one you track that has data."
    static let gaugePerTool = "One gauge per tool"
    static let gaugePerToolCaption = "A small gauge for each tool you track, side by side. The menu bar item gets wider."

    // General › Widgets
    static let widgetsHowTo = "Add Headroom widgets from the desktop: Control-click it and choose Edit Widgets, then search for Headroom."
    static let widgetShowsSessionNames = "Show session names in widgets"

    // Tools
    static let trackClaude = "Track Claude"
    static let trackCodex = "Track Codex"
    static let trackCopilot = "Track Copilot"
    static let codexCaption = "Headroom reads only Codex's session files. The folder also holds your Codex sign-in; Headroom never opens it and never contacts OpenAI."
    static let copilotCLICaption = "Connect session activity separately from GitHub usage. Supports Copilot CLI and the Copilot desktop app. Adds one hook file to ~/.copilot; Disconnect removes it. New sessions pick up the connection."
    static let developmentBuildFooter = "Development build: not sandboxed, so Headroom reads these folders directly."

    /// Tools' footer (1.1 §6.4): without Copilot usage (no Client ID) the GitHub clause goes, without Copilot CLI
    /// support "and Connect sessions" does.
    static func toolsFooter(copilotUsage: Bool, copilotCLI: Bool) -> String {
        let writers = copilotCLI
            ? "Connect terminal and Connect sessions add files only after asking you"
            : "Connect terminal adds files only after asking you"
        let network = copilotUsage ? ", and Copilot usage talks to GitHub only when you connect it" : ""
        return "Headroom only reads these folders. \(writers)\(network)."
    }

    // About
    static let nonAffiliation = "Headroom isn't made by or affiliated with Anthropic, OpenAI or GitHub."
}
