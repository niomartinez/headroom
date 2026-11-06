import Foundation

/// A data source Headroom could not read. The UI hides numbers it can't trust instead of guessing.
public enum DataIssue: String, Sendable, Equatable, Hashable, Codable {
    /// No access to `~/.claude` (sandbox grant missing or folder absent).
    case claudeCodeFolderUnavailable
    /// No access to `~/Library/Application Support/Claude` although the Claude desktop app is installed.
    case desktopFolderUnavailable
    /// `plan-usage-history.json` exists but its format is unknown.
    case desktopUsageUnrecognized
    /// `~/.claude/sessions` could not be listed.
    case sessionRegistryUnreadable
    /// Codex is tracked but `~/.codex` isn't readable (1.1 §3.6): the access row.
    case codexFolderUnavailable
    /// The newest Codex `rate_limits` decodes to no window and isn't a known empty bucket (1.1 §3.4).
    case codexUsageUnrecognized
    /// `~/.codex/sessions` could not be listed (1.1 §3.6): "Can't read Codex sessions".
    case codexSessionsUnreadable
    /// Copilot CLI is connected but the `~/.copilot` grant isn't readable (1.1 §4.9).
    case copilotFolderUnavailable
}

/// Which folders the app can currently read (sandbox grants, or direct access in Debug builds).
public struct AccessState: Sendable, Equatable, Codable {
    public var claudeDirectoryReadable: Bool
    public var desktopDirectoryReadable: Bool
    /// Whether the Claude desktop app is installed. When it isn't, an unreadable desktop folder is
    /// expected (terminal-only users) and is not reported as `DataIssue.desktopFolderUnavailable`.
    public var desktopAppInstalled: Bool
    /// `~/.codex` (or the folder the user picked for it) can be read (1.1 §3.1).
    public var codexDirectoryReadable: Bool
    /// `~/.codex` exists or the Codex app is installed (1.1 §3.1): the Codex offer's condition.
    public var codexInstalled: Bool
    /// The Copilot CLI folder (`~/.copilot` or the user's pick) can be read (1.1 §4.9).
    public var copilotDirectoryReadable: Bool
    /// `~/.copilot` exists (1.1 §4.9).
    public var copilotCLIInstalled: Bool

    public init(
        claudeDirectoryReadable: Bool,
        desktopDirectoryReadable: Bool,
        desktopAppInstalled: Bool = true,
        codexDirectoryReadable: Bool = false,
        codexInstalled: Bool = false,
        copilotDirectoryReadable: Bool = false,
        copilotCLIInstalled: Bool = false
    ) {
        self.claudeDirectoryReadable = claudeDirectoryReadable
        self.desktopDirectoryReadable = desktopDirectoryReadable
        self.desktopAppInstalled = desktopAppInstalled
        self.codexDirectoryReadable = codexDirectoryReadable
        self.codexInstalled = codexInstalled
        self.copilotDirectoryReadable = copilotDirectoryReadable
        self.copilotCLIInstalled = copilotCLIInstalled
    }

    private enum CodingKeys: String, CodingKey {
        case claudeDirectoryReadable, desktopDirectoryReadable, desktopAppInstalled
        case codexDirectoryReadable, codexInstalled, copilotDirectoryReadable, copilotCLIInstalled
    }

    /// 1.0 JSON (no Codex or Copilot fields) decodes with those false.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        claudeDirectoryReadable = try container.decode(Bool.self, forKey: .claudeDirectoryReadable)
        desktopDirectoryReadable = try container.decode(Bool.self, forKey: .desktopDirectoryReadable)
        desktopAppInstalled = try container.decode(Bool.self, forKey: .desktopAppInstalled)
        codexDirectoryReadable = try container.decodeIfPresent(Bool.self, forKey: .codexDirectoryReadable) ?? false
        codexInstalled = try container.decodeIfPresent(Bool.self, forKey: .codexInstalled) ?? false
        copilotDirectoryReadable = try container.decodeIfPresent(Bool.self, forKey: .copilotDirectoryReadable) ?? false
        copilotCLIInstalled = try container.decodeIfPresent(Bool.self, forKey: .copilotCLIInstalled) ?? false
    }

    public static let full = AccessState(claudeDirectoryReadable: true, desktopDirectoryReadable: true)
    public static let none = AccessState(claudeDirectoryReadable: false, desktopDirectoryReadable: false)
}

/// Everything the UI shows, computed in one pass.
public struct HeadroomSnapshot: Sendable, Equatable, Codable {
    /// Claude's limits (`.empty` when Claude isn't tracked).
    public var plan: PlanUsage
    /// Every tracked tool's sessions, already sorted for display (spec §3.3), context filled in where known.
    public var sessions: [SessionInfo]
    /// `true` when the terminal bridge (status line + hooks) is installed.
    public var terminalBridgeConnected: Bool
    public var issues: Set<DataIssue>
    public var generatedAt: Date
    /// Codex's limits; nil when Codex isn't tracked (1.1 §2.2).
    public var codex: ToolUsage?
    /// Copilot's usage; nil when Copilot isn't tracked.
    public var copilot: ToolUsage?
    /// Whether Claude is tracked (Settings › Tools › Track Claude). True in 1.0 snapshots.
    public var claudeTracked: Bool

    public init(
        plan: PlanUsage,
        sessions: [SessionInfo],
        terminalBridgeConnected: Bool,
        issues: Set<DataIssue>,
        generatedAt: Date,
        codex: ToolUsage? = nil,
        copilot: ToolUsage? = nil,
        claudeTracked: Bool = true
    ) {
        self.plan = plan
        self.sessions = sessions
        self.terminalBridgeConnected = terminalBridgeConnected
        self.issues = issues
        self.generatedAt = generatedAt
        self.codex = codex
        self.copilot = copilot
        self.claudeTracked = claudeTracked
    }

    private enum CodingKeys: String, CodingKey {
        case plan, sessions, terminalBridgeConnected, issues, generatedAt, codex, copilot, claudeTracked
    }

    /// 1.0 JSON decodes as a Claude-only snapshot: no Codex, no Copilot, Claude tracked.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plan = try container.decode(PlanUsage.self, forKey: .plan)
        sessions = try container.decode([SessionInfo].self, forKey: .sessions)
        terminalBridgeConnected = try container.decode(Bool.self, forKey: .terminalBridgeConnected)
        issues = try container.decode(Set<DataIssue>.self, forKey: .issues)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        codex = try container.decodeIfPresent(ToolUsage.self, forKey: .codex)
        copilot = try container.decodeIfPresent(ToolUsage.self, forKey: .copilot)
        claudeTracked = try container.decodeIfPresent(Bool.self, forKey: .claudeTracked) ?? true
    }

    public static func empty(at date: Date) -> HeadroomSnapshot {
        HeadroomSnapshot(plan: .empty, sessions: [], terminalBridgeConnected: false, issues: [], generatedAt: date)
    }

    /// The tracked tools in display order (Claude, Codex, Copilot).
    public var trackedTools: [ToolID] {
        ToolID.allCases.filter { tool in
            switch tool {
            case .claude: claudeTracked
            case .codex: codex != nil
            case .copilot: copilot != nil
            }
        }
    }

    /// Only Claude is tracked: the pill and panel render exactly as in 1.0 (1.1 §0.1).
    public var isClaudeOnly: Bool { trackedTools == [.claude] }

    /// Two or more tools are tracked: the multi-tool panel and "No sessions running" (1.1 §6.3), and limit moments
    /// that name their tool (§6.2).
    public var isMultiTool: Bool { trackedTools.count > 1 }

    /// A tracked tool's limits: Claude's `plan` as a `ToolUsage` (`ToolUsage(claude:)`), or `codex` / `copilot`.
    /// Nil when the tool isn't tracked.
    public func usage(for tool: ToolID) -> ToolUsage? {
        switch tool {
        case .claude: claudeTracked ? ToolUsage(claude: plan) : nil
        case .codex: codex
        case .copilot: copilot
        }
    }

    /// Every limit as of `now` (`PlanUsage.rolledOver(now:)`, `ToolUsage.rolledOver(now:)`), for widget timeline
    /// entries dated after the snapshot. Sessions are unchanged.
    public func rolledOver(now: Date) -> HeadroomSnapshot {
        var rolled = self
        rolled.plan = plan.rolledOver(now: now)
        rolled.codex = codex?.rolledOver(now: now)
        rolled.copilot = copilot?.rolledOver(now: now)
        return rolled
    }

    /// The snapshot with the waiting sessions in `dismissedIDs` read as idle, in display order again (1.1 §14.4):
    /// the user dismissed that wait, so it leaves the amber dot, the count and `waitingCount`. Sessions that aren't
    /// waiting are untouched, so a dismissal never hides a session that went back to work.
    public func applyingDismissals(_ dismissedIDs: Set<String>) -> HeadroomSnapshot {
        guard sessions.contains(where: { dismissedIDs.contains($0.id) && $0.activity == .waitingForInput }) else {
            return self
        }
        var shown = self
        shown.sessions = sessions.map { session in
            guard dismissedIDs.contains(session.id), session.activity == .waitingForInput else { return session }
            var idle = session
            idle.activity = .idle
            return idle
        }.sortedForDisplay()
        return shown
    }

    public var workingCount: Int { sessions.filter { $0.activity == .working }.count }
    public var waitingCount: Int { sessions.filter { $0.activity == .waitingForInput }.count }
    /// Working + waiting: the number shown next to the dot.
    public var activeCount: Int { workingCount + waitingCount }
}

/// A short-lived event the pill announces (spec §1.1, §3.4; 1.1 §6.2).
///
/// Whether a limit moment names its tool is decided where it is shown, from the snapshot on screen
/// (`HeadroomSnapshot.isMultiTool`), for Claude's `limitCrossed` and `toolLimitCrossed` alike: "Weekly at 90%" with
/// one tool tracked, "Codex weekly at 90%" or "Claude 5-hour at 90%" with two or more. Session moments never name
/// the tool on screen; VoiceOver does ("Codex session ledger finished", `ToolID(sessionID:)`).
public enum Moment: Sendable, Equatable, Hashable, Codable {
    case sessionFinished(sessionID: String, name: String)
    case sessionNeedsInput(sessionID: String, name: String)
    /// A Claude limit. `percent` is 90 or 100.
    case limitCrossed(kind: LimitKind, percent: Int)
    /// A Codex or Copilot limit (1.1 §6.2). `percent` is 90 or 100. Copilot at 100 % is "used up", never "reached":
    /// Copilot keeps working on paid extra usage ("Monthly credits used up", "Copilot credits used up").
    case toolLimitCrossed(tool: ToolID, window: WindowKind, percent: Int)
}
