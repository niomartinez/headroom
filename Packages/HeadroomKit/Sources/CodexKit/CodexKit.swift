import Foundation
import HeadroomModel

// CodexKit: OpenAI Codex limits, sessions and context from the Codex folder, read only (1.1 §3).
//
// Pipeline: `CodexReader.read(now:)` walks `sessions/` (at most every 30 s, or when the writer locks change),
// head-reads each rollout's `session_meta` once and tail-reads what changed, then returns the Codex `ToolUsage`
// (§3.4), the shown sessions (§3.5) and the issues (§3.6). Every URL comes from `CodexPaths` (§3.1).

/// Tells whether Codex is running (1.1 §3.5 liveness): the Codex app (bundle id `com.openai.codex`, checked by
/// the app with NSWorkspace, which the package can't use) or any process named `codex`.
public protocol CodexRuntimeProbing: Sendable {
    /// True when Codex runs, false when it certainly doesn't, nil when the process list can't be read (the sandbox
    /// may deny it). Nil selects the recency fallbacks of the liveness table.
    func codexRunning() -> Bool?
}

/// The real `CodexRuntimeProbing` (1.1 §3.5). The app supplies `appIsRunning`, its NSWorkspace check for bundle id
/// `com.openai.codex`; the process half (`sysctl KERN_PROC_ALL`) lives here, so it is tested with the rest of the
/// liveness rules. headroom-dump and `SnapshotBuilder(paths:)` pass `{ false }`: processes only.
public struct CodexRuntimeProbe: CodexRuntimeProbing {
    private let appIsRunning: @Sendable () -> Bool

    public init(appIsRunning: @escaping @Sendable () -> Bool) {
        self.appIsRunning = appIsRunning
    }

    /// True when the Codex app runs or `codexProcessExists()` is true; nil when the app doesn't run and the process
    /// list can't be read.
    public func codexRunning() -> Bool? {
        appIsRunning() ? true : Self.codexProcessExists()
    }

    /// Whether any process's `p_comm` is `codex` (the Desktop app runs one too), from `sysctl(KERN_PROC_ALL)`;
    /// nil when the process list can't be read, which the sandbox may deny (live check L4).
    public static func codexProcessExists() -> Bool? {
        ProcessList.commandNames().map(ProcessList.containsCodex)
    }
}

/// One pass over the Codex folder.
public struct CodexReading: Sendable, Equatable {
    /// `ToolUsage(tool: .codex, ...)`, already rolled over as of the read's `now`.
    public var usage: ToolUsage
    /// Shown Codex threads (`tool == .codex`, ids `codex:<thread uuid>`), unsorted: the store sorts every tool's
    /// sessions together.
    public var sessions: [SessionInfo]
    /// `codexSessionsUnreadable`, `codexUsageUnrecognized`. The store adds `codexFolderUnavailable` itself, since
    /// it doesn't read at all without access.
    public var issues: [DataIssue]

    public init(usage: ToolUsage, sessions: [SessionInfo], issues: [DataIssue]) {
        self.usage = usage
        self.sessions = sessions
        self.issues = issues
    }
}

/// What `SnapshotBuilder` reads Codex through, so store tests can inject a fake.
public protocol CodexReadingProviding: AnyObject {
    func read(now: Date) -> CodexReading
}
