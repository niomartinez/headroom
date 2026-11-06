import Darwin
import Foundation

/// The user's real home directory. In a sandboxed app `NSHomeDirectory()` is the container,
/// so this reads the password database instead.
public enum RealHome {
    public static var url: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }
}

/// Every Claude file location Headroom reads or writes (spec §2).
public struct ClaudePaths: Sendable, Equatable {
    /// `~/.claude`
    public var claudeDirectory: URL
    /// `~/Library/Application Support/Claude`
    public var desktopSupportDirectory: URL

    public init(claudeDirectory: URL, desktopSupportDirectory: URL) {
        self.claudeDirectory = claudeDirectory
        self.desktopSupportDirectory = desktopSupportDirectory
    }

    public static func standard(home: URL = RealHome.url) -> ClaudePaths {
        ClaudePaths(
            claudeDirectory: home.appendingPathComponent(".claude", isDirectory: true),
            desktopSupportDirectory: home
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("Claude", isDirectory: true)
        )
    }

    public var sessionsDirectory: URL { claudeDirectory.appendingPathComponent("sessions", isDirectory: true) }
    public var projectsDirectory: URL { claudeDirectory.appendingPathComponent("projects", isDirectory: true) }
    public var settingsFile: URL { claudeDirectory.appendingPathComponent("settings.json") }
    public var bridgeDirectory: URL { claudeDirectory.appendingPathComponent("headroom", isDirectory: true) }
    public var bridgeSessionsDirectory: URL { bridgeDirectory.appendingPathComponent("sessions", isDirectory: true) }
    public var statusLineLatestFile: URL { bridgeDirectory.appendingPathComponent("statusline-latest.json") }
    public var planUsageHistoryFile: URL { desktopSupportDirectory.appendingPathComponent("plan-usage-history.json") }
}

/// The only builder of URLs into the Codex folder (1.1 §3.1). CodexKit opens nothing else there: never
/// `auth.json`, `config.toml`, `models_cache.json`, `*.sqlite*` or `ipc/` (1.1 §0.1 invariant 2). The one exception,
/// outside CodexKit: `SessionViewReader` reads `.codex-global-state.json` for the Codex app's unread thread ids only
/// (1.1.2, §14.15).
public struct CodexPaths: Sendable, Equatable {
    /// `~/.codex`, or the folder the user picked for `CODEX_HOME` (any folder with a `sessions/` subfolder).
    public var codexDirectory: URL

    public init(codexDirectory: URL) {
        self.codexDirectory = codexDirectory
    }

    public static func standard(home: URL = RealHome.url) -> CodexPaths {
        CodexPaths(codexDirectory: home.appendingPathComponent(".codex", isDirectory: true))
    }

    /// `sessions/`: `YYYY/MM/DD/rollout-*.jsonl`, walked, stat'ed, and read at the head and the tail only.
    public var sessionsDirectory: URL { codexDirectory.appendingPathComponent("sessions", isDirectory: true) }
    /// `session_index.jsonl`: thread titles (tail read).
    public var sessionIndexFile: URL { codexDirectory.appendingPathComponent("session_index.jsonl") }
    /// `external_agent_session_imports.json`: import exclusion (whole file, at most 4 MB).
    public var importsFile: URL { codexDirectory.appendingPathComponent("external_agent_session_imports.json") }
    /// `.codex-global-state.json`: the Codex app's state; only its unread thread ids are read (`SessionViewReader`).
    public var globalStateFile: URL { codexDirectory.appendingPathComponent(".codex-global-state.json") }
    /// `thread-writer-locks/`: listed and stat'ed only, never opened (a lock would break Codex's `try_lock`).
    public var writerLocksDirectory: URL {
        codexDirectory.appendingPathComponent("thread-writer-locks", isDirectory: true)
    }

    /// `sessions/YYYY/MM/DD/` for `date`'s day in `calendar`'s time zone. Codex names day folders in local time,
    /// so pass the local calendar (the default) and try the neighbouring days too (1.1 §3.5).
    public func sessionsDayDirectory(for date: Date, calendar: Calendar = .current) -> URL {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return sessionsDirectory
            .appendingPathComponent(String(format: "%04d", day.year ?? 0), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", day.month ?? 0), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", day.day ?? 0), isDirectory: true)
    }

    /// `thread-writer-locks/<thread id>.lock`, for `stat` only: never open it.
    public func writerLockFile(threadID: String) -> URL {
        writerLocksDirectory.appendingPathComponent("\(threadID).lock")
    }
}

/// The only builder of URLs into the Copilot CLI folder (1.1 §4.9). Headroom writes only `hooks/headroom.json` and
/// `headroom/**`, reads only `headroom/sessions/*.hook.json` and lists only the names in `logs/`. It never opens
/// `config.json` (it can hold auth), `settings.json`, `session-state/` or `session-store.db`.
public struct CopilotPaths: Sendable, Equatable {
    /// `~/.copilot`, or the folder the user picked for `COPILOT_HOME`.
    public var copilotDirectory: URL

    public init(copilotDirectory: URL) {
        self.copilotDirectory = copilotDirectory
    }

    public static func standard(home: URL = RealHome.url) -> CopilotPaths {
        CopilotPaths(copilotDirectory: home.appendingPathComponent(".copilot", isDirectory: true))
    }

    /// `hooks/`: created when missing; Headroom touches only its own file in it.
    public var hooksDirectory: URL { copilotDirectory.appendingPathComponent("hooks", isDirectory: true) }
    /// `hooks/headroom.json`: Headroom's own hooks file, so the user's settings stay untouched.
    public var hooksFile: URL { hooksDirectory.appendingPathComponent("headroom.json") }
    /// `headroom/`: the bridge's folder, removed whole on Disconnect.
    public var bridgeDirectory: URL { copilotDirectory.appendingPathComponent("headroom", isDirectory: true) }
    /// `headroom/bridge.sh`.
    public var bridgeScriptFile: URL { bridgeDirectory.appendingPathComponent("bridge.sh") }
    /// `headroom/sessions/`: the bridge's `<sessionId>.hook.json` records.
    public var bridgeSessionsDirectory: URL { bridgeDirectory.appendingPathComponent("sessions", isDirectory: true) }
    /// `logs/`: list the `process-<epochMs>-<pid>.log` names only, never open them.
    public var logsDirectory: URL { copilotDirectory.appendingPathComponent("logs", isDirectory: true) }
}
