import Foundation

/// Which local sources the user tracks and where their granted folders are (Settings › Tools, 1.1 §7). The app
/// assembles one per poll from its preferences and grants. Copilot usage isn't a local source: the app's
/// `CopilotService` hands its `ToolUsage` to `SnapshotBuilder.build(access:sources:copilot:now:)`.
public struct SourceSelection: Sendable, Equatable {
    /// Track Claude: the desktop app's usage history, `~/.claude` sessions and the terminal bridge.
    public var claude: Bool
    /// Track Codex: limits and sessions from the Codex folder.
    public var codex: Bool
    /// Copilot CLI sessions through the Copilot bridge (Track Copilot, with Connect Copilot CLI done). Ignored in a
    /// build without `HEADROOM_COPILOT_CLI` (gate G2, 1.1 §4.9).
    public var copilotCLI: Bool
    /// The granted Codex folder (`~/.codex` or the user's pick, 1.1 §3.1); nil without a grant. Read only while
    /// `codex` is on and `AccessState.codexDirectoryReadable`; the builder keeps its Codex caches while it stays the
    /// same.
    public var codexHome: URL?
    /// The granted Copilot CLI folder (`~/.copilot` or the user's pick, 1.1 §4.9); nil without a grant. Read only
    /// while `copilotCLI` is on and `AccessState.copilotDirectoryReadable`.
    public var copilotCLIHome: URL?

    public init(
        claude: Bool = true, codex: Bool = false, copilotCLI: Bool = false, codexHome: URL? = nil,
        copilotCLIHome: URL? = nil
    ) {
        self.claude = claude
        self.codex = codex
        self.copilotCLI = copilotCLI
        self.codexHome = codexHome
        self.copilotCLIHome = copilotCLIHome
    }

    /// 1.0: Claude only.
    public static let claudeOnly = SourceSelection()

    /// `copilotCLI`, or false in a build without Copilot CLI support.
    var readsCopilotCLI: Bool {
        #if HEADROOM_COPILOT_CLI
        copilotCLI
        #else
        false
        #endif
    }
}
