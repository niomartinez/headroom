import Foundation

/// Where a session runs.
public enum SessionOrigin: String, Sendable, Codable {
    /// The Claude desktop app's Code tab (found via `~/.claude/sessions`, spec §2.2), or the Codex app (1.1 §3.5).
    case desktop
    /// `claude` in a terminal (found via the bridge's hook/status line files, spec §2.4–2.5), the Codex CLI or
    /// Copilot CLI (1.1 §3.5, §4.9).
    case terminal
}

public enum SessionActivity: String, Sendable, Codable {
    case working
    case waitingForInput
    case idle

    /// Spec §3.3 sort order.
    public var sortRank: Int {
        switch self {
        case .working: 0
        case .waitingForInput: 1
        case .idle: 2
        }
    }
}

/// How full a session's context window is (spec §2.3).
public struct ContextUsage: Sendable, Equatable, Codable {
    public var usedTokens: Int
    public var windowTokens: Int
    public var model: String?
    /// `true` when `windowTokens` came from the session's own status line.
    public var windowIsExact: Bool
    /// Timestamp of the transcript entry the numbers came from, if known.
    public var observedAt: Date?
    /// `true` when nothing is known about the model's window, so `windowTokens` is the standard
    /// 200k as a guess (spec §2.3). A percent of it would mislead: the UI shows the token count only.
    public var windowIsAssumed: Bool
    /// Tokens the tool counts as always present and leaves out of its own percent (Codex: 12,000, 1.1 §3.5).
    /// 0 for Claude.
    public var baselineTokens: Int

    public init(
        usedTokens: Int,
        windowTokens: Int,
        model: String?,
        windowIsExact: Bool,
        observedAt: Date?,
        windowIsAssumed: Bool = false,
        baselineTokens: Int = 0
    ) {
        self.usedTokens = usedTokens
        self.windowTokens = windowTokens
        self.model = model
        self.windowIsExact = windowIsExact
        self.observedAt = observedAt
        self.windowIsAssumed = windowIsAssumed
        self.baselineTokens = baselineTokens
    }

    private enum CodingKeys: String, CodingKey {
        case usedTokens, windowTokens, model, windowIsExact, observedAt, windowIsAssumed, baselineTokens
    }

    /// JSON written before `windowIsAssumed` or `baselineTokens` existed decodes as a window that is not assumed,
    /// with no baseline.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedTokens = try container.decode(Int.self, forKey: .usedTokens)
        windowTokens = try container.decode(Int.self, forKey: .windowTokens)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        windowIsExact = try container.decode(Bool.self, forKey: .windowIsExact)
        observedAt = try container.decodeIfPresent(Date.self, forKey: .observedAt)
        windowIsAssumed = try container.decodeIfPresent(Bool.self, forKey: .windowIsAssumed) ?? false
        baselineTokens = try container.decodeIfPresent(Int.self, forKey: .baselineTokens) ?? 0
    }

    /// 0...100. With a baseline B (Codex), Codex's own formula: `max(0, used − B) / (W − B)`, clamped; the raw
    /// value reaches 105 % before auto-compaction (1.1 §3.5). Without one, `used / W`, clamped.
    public var percent: Double {
        guard baselineTokens > 0 else {
            guard windowTokens > 0 else { return 0 }
            return min(100, max(0, Double(usedTokens) / Double(windowTokens) * 100))
        }
        let usable = windowTokens - baselineTokens
        guard usable > 0 else { return 0 }
        let used = max(0, usedTokens - baselineTokens)
        return min(100, Double(used) / Double(usable) * 100)
    }
}

public struct SessionInfo: Sendable, Equatable, Codable, Identifiable {
    /// Unique across tools. Claude Code: the session id (transcript file name without `.jsonl`), unprefixed as in
    /// 1.0. Codex: `codex:<thread uuid>`. Copilot CLI: `copilot:<session uuid>` (1.1 §2.2).
    public var id: String
    /// Display name: the desktop session title, or the project folder name for terminal sessions.
    public var name: String
    /// The session's working directory.
    public var projectPath: String?
    public var origin: SessionOrigin
    public var activity: SessionActivity
    /// When the current activity started / was last updated.
    public var activitySince: Date?
    public var startedAt: Date?
    public var pid: Int32?
    public var transcriptPath: String?
    public var context: ContextUsage?
    /// The tool running the session.
    public var tool: ToolID
    /// The Claude desktop app's own id for the session (`local_<uuid>`, the registry's `hostSessionId`), for its
    /// `claude://code/continue` link (1.1 §14.3). Nil for terminal sessions and other tools. Never written to the
    /// widget file.
    public var desktopSessionID: String?

    public init(
        id: String,
        name: String,
        projectPath: String?,
        origin: SessionOrigin,
        activity: SessionActivity,
        activitySince: Date?,
        startedAt: Date?,
        pid: Int32?,
        transcriptPath: String?,
        context: ContextUsage?,
        tool: ToolID = .claude,
        desktopSessionID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.projectPath = projectPath
        self.origin = origin
        self.activity = activity
        self.activitySince = activitySince
        self.startedAt = startedAt
        self.pid = pid
        self.transcriptPath = transcriptPath
        self.context = context
        self.tool = tool
        self.desktopSessionID = desktopSessionID
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, projectPath, origin, activity, activitySince, startedAt, pid, transcriptPath, context, tool
        case desktopSessionID
    }

    /// JSON written before `tool` existed (1.0) decodes as a Claude session; before `desktopSessionID`, without one.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath)
        origin = try container.decode(SessionOrigin.self, forKey: .origin)
        activity = try container.decode(SessionActivity.self, forKey: .activity)
        activitySince = try container.decodeIfPresent(Date.self, forKey: .activitySince)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        pid = try container.decodeIfPresent(Int32.self, forKey: .pid)
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        context = try container.decodeIfPresent(ContextUsage.self, forKey: .context)
        tool = try container.decodeIfPresent(ToolID.self, forKey: .tool) ?? .claude
        desktopSessionID = try container.decodeIfPresent(String.self, forKey: .desktopSessionID)
    }

    /// The folder to show next to the name: nil for scratch workspaces, or when it equals the name.
    public var projectName: String? {
        guard let projectPath, !projectPath.isEmpty else { return nil }
        if projectPath.contains("/scratch-workspaces/") { return nil }
        let last = URL(fileURLWithPath: projectPath).lastPathComponent
        if last.isEmpty || last == "/" || last == name { return nil }
        return last
    }
}

public extension Array where Element == SessionInfo {
    /// Spec §3.3: working, then waiting, then idle; most recent activity first inside a group.
    func sortedForDisplay() -> [SessionInfo] {
        sorted { a, b in
            if a.activity.sortRank != b.activity.sortRank { return a.activity.sortRank < b.activity.sortRank }
            let da = a.activitySince ?? .distantPast
            let db = b.activitySince ?? .distantPast
            if da != db { return da > db }
            return a.id < b.id
        }
    }
}
