import Foundation
import HeadroomModel
import SessionKit

/// A running app a session can be brought forward in (1.1 §14.3): the terminal or editor a CLI session runs in, or
/// the Claude or Codex app.
struct HostApp: Sendable, Equatable {
    var pid: Int32
    var bundleIdentifier: String?
    /// What the row says: "Terminal", "iTerm", "VS Code" (`HostAppNames`).
    var name: String
    /// Where Launch Services opens it from; nil for an app without a bundle.
    var bundleURL: URL?
    /// A Dock app (`NSApplication.ActivationPolicy.regular`). Helpers and agents ("Claude Helper", menu bar apps) are
    /// passed over on the way up.
    var isRegular: Bool
}

/// Where a click on a session row goes (1.1 §14.3). The panel shows `title` in place of the context bar on hover
/// ("Open in Claude ↗") and at the start of the row's tooltip.
enum SessionTarget: Sendable, Equatable {
    /// A deep link to the session itself, opened by `appName` (the scheme's handler). `fallback` is brought forward
    /// when the link can't be opened.
    case link(URL, appName: String, fallback: HostApp?)
    /// Bring `app` forward: the terminal a CLI session runs in ("Show in Terminal"), or the session's own app when
    /// there is no link for it ("Open in Claude").
    case app(HostApp, opensSession: Bool)

    var title: String {
        switch self {
        case let .link(_, appName, _): "Open in \(appName)"
        case let .app(app, opensSession): opensSession ? "Open in \(app.name)" : "Show in \(app.name)"
        }
    }
}

/// The deep links (1.1 §14.3), built in one place so they are easy to re-check when the apps change.
enum SessionLinks {
    /// The Claude app handles `claude://code/continue?session=local_<uuid>`: it only navigates, like its own Dock menu
    /// and Spotlight entries. The id must look like Claude's own ids, so nothing else is ever passed to it.
    static func claudeDesktop(sessionID: String?) -> URL? {
        guard let sessionID, isClaudeDesktopID(sessionID) else { return nil }
        return URL(string: "claude://code/continue?session=\(sessionID)")
    }

    /// `^local_[A-Za-z0-9-]{1,64}$`, the check the Claude app makes itself.
    static func isClaudeDesktopID(_ id: String) -> Bool {
        let prefix = "local_"
        guard id.hasPrefix(prefix) else { return false }
        let rest = id.dropFirst(prefix.count)
        return (1...64).contains(rest.count) && rest.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    /// The Codex app (ChatGPT.app) handles `codex://threads/<thread uuid>`; Headroom's Codex ids are
    /// `codex:<thread uuid>`.
    static func codexThread(sessionID: String) -> URL? {
        let prefix = "codex:"
        guard sessionID.hasPrefix(prefix), let uuid = UUID(uuidString: String(sessionID.dropFirst(prefix.count))) else {
            return nil
        }
        return URL(string: "codex://threads/\(uuid.uuidString.lowercased())")
    }
}

/// The short names rows use for host apps (1.1 §14.3): an app's own name can be long or odd ("Code" for VS Code).
enum HostAppNames {
    static let iTermBundleIdentifier = "com.googlecode.iterm2"

    private static let names: [String: String] = [
        "com.apple.Terminal": "Terminal",
        iTermBundleIdentifier: "iTerm",
        "com.mitchellh.ghostty": "Ghostty",
        "dev.warp.Warp-Stable": "Warp",
        "com.microsoft.VSCode": "VS Code",
        "com.microsoft.VSCodeInsiders": "VS Code",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "dev.zed.Zed": "Zed",
        ClaudeDesktopApp.bundleIdentifier: "Claude",
    ]

    /// The table's name, else the app's own (`localizedName`), else "the app".
    static func name(bundleIdentifier: String?, localizedName: String?) -> String {
        if let bundleIdentifier, let name = names[bundleIdentifier] { return name }
        if let localizedName, !localizedName.isEmpty { return localizedName }
        return "the app"
    }
}

/// Finds where a session can be opened (1.1 §14.3). Pure: the process table and the running apps are injected, so
/// tests use fakes and the app uses `SystemProcessTable` and `NSRunningApplication`.
struct SessionTargetResolver {
    /// The process table (`SystemProcessTable`).
    var processes: any ProcessTableReading
    /// The running app with this pid, if the pid is an app's.
    var appForPID: (Int32) -> HostApp?
    /// A running app with this bundle id.
    var runningApp: (String) -> HostApp?
    /// The display name of the app that opens `url` ("ChatGPT" for `codex://`); nil when no app does.
    var handlerName: (URL) -> String?

    /// What one resolution pass reads once and shares between rows: the whole process list (read only for a Codex
    /// CLI row without a pid) and each link scheme's handler app.
    private struct Lookups {
        /// Outer nil: not read yet; inner nil: the list can't be read.
        var processList: [ProcessEntry]??
        var handlerNames: [String: String?] = [:]
    }

    /// Nil when Headroom can't tell where the session runs: tmux, screen, ssh, a process adopted by launchd, a pid
    /// that is gone. Never for sample data, whose sessions don't exist.
    func target(for session: SessionInfo, sampleData: Bool) -> SessionTarget? {
        targets(for: [session], sampleData: sampleData)[session.id]
    }

    /// Every row's target at once (the panel opening), keyed by session id; rows without one are left out. The
    /// process list is read at most once and each link's handler looked up once per scheme, for all the rows.
    func targets(for sessions: [SessionInfo], sampleData: Bool) -> [String: SessionTarget] {
        guard !sampleData else { return [:] }
        var lookups = Lookups()
        var targets: [String: SessionTarget] = [:]
        for session in sessions {
            targets[session.id] = target(for: session, lookups: &lookups)
        }
        return targets
    }

    private func target(for session: SessionInfo, lookups: inout Lookups) -> SessionTarget? {
        switch (session.tool, session.origin) {
        case (.claude, .desktop):
            return claudeDesktop(session, lookups: &lookups)
        case (.codex, .desktop):
            return codexDesktop(session, lookups: &lookups)
        case (_, .terminal):
            if let pid = session.pid { return terminalHost(of: pid).map { .app($0, opensSession: false) } }
            if session.tool == .codex {
                return codexCLIHost(session, lookups: &lookups).map { .app($0, opensSession: false) }
            }
            return nil
        case (.copilot, .desktop):
            return nil
        }
    }

    /// The session's own link; without one (no id, or an id Claude wouldn't accept) Claude itself comes forward.
    private func claudeDesktop(_ session: SessionInfo, lookups: inout Lookups) -> SessionTarget? {
        let claude = runningApp(ClaudeDesktopApp.bundleIdentifier)
        if let url = SessionLinks.claudeDesktop(sessionID: session.desktopSessionID),
           handlerName(url, lookups: &lookups) != nil
        {
            return .link(url, appName: "Claude", fallback: claude)
        }
        return claude.map { .app($0, opensSession: true) }
    }

    /// The thread's link, named by the app that opens it (ChatGPT today); else the Codex app comes forward.
    private func codexDesktop(_ session: SessionInfo, lookups: inout Lookups) -> SessionTarget? {
        let codex = runningApp(CodexApp.bundleIdentifier)
        if let url = SessionLinks.codexThread(sessionID: session.id), let name = handlerName(url, lookups: &lookups) {
            return .link(url, appName: name, fallback: codex)
        }
        return codex.map { .app($0, opensSession: true) }
    }

    /// `handlerName`, once per URL scheme in a pass: every link of a scheme opens in the same app.
    private func handlerName(_ url: URL, lookups: inout Lookups) -> String? {
        let scheme = url.scheme?.lowercased() ?? ""
        if let known = lookups.handlerNames[scheme] { return known }
        let name = handlerName(url)
        lookups.handlerNames[scheme] = name
        return name
    }

    /// The first Dock app above `pid`, nearest first. iTerm2 runs its shells under `iTermServer-<version>`, which
    /// launchd adopts, so that name stands for iTerm2.
    func terminalHost(of pid: Int32) -> HostApp? {
        for process in ProcessAncestry.chain(from: pid, in: processes) {
            if process.command.hasPrefix("iTermServer") {
                return runningApp(HostAppNames.iTermBundleIdentifier).flatMap { $0.isRegular ? $0 : nil }
            }
            if let app = appForPID(process.pid), app.isRegular {
                return app
            }
        }
        return nil
    }

    /// Codex CLI sessions come from rollout files, without a pid: a `codex` process working in the session's folder,
    /// outside the Codex app, stands for it. Only when every such process runs in the same app; two terminals in the
    /// same folder can't be told apart.
    private func codexCLIHost(_ session: SessionInfo, lookups: inout Lookups) -> HostApp? {
        if lookups.processList == nil { lookups.processList = .some(processes.all()) }
        guard let folder = session.projectPath.map(Self.normalized), let all = lookups.processList ?? nil else {
            return nil
        }
        var hosts: [Int32: HostApp] = [:]
        for process in all where process.command == "codex" {
            guard processes.workingDirectory(pid: process.pid).map(Self.normalized) == folder else { continue }
            let chain = ProcessAncestry.chain(from: process.pid, in: processes)
            // The Codex app runs its own `codex`: those threads are the app's, not a terminal's.
            let inCodexApp = chain.contains { appForPID($0.pid)?.bundleIdentifier == CodexApp.bundleIdentifier }
            guard !inCodexApp else { continue }
            guard let host = terminalHost(of: process.pid) else { return nil }
            hosts[host.pid] = host
        }
        return hosts.count == 1 ? hosts.values.first : nil
    }

    /// A folder path without its trailing slash.
    private static func normalized(_ path: String) -> String {
        var path = path
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}

/// What opening a session asks of the system: `NSWorkspace` in the app, a recorder in tests.
@MainActor
protocol SessionWorkspace {
    /// Opens `url` in its handler app, bringing that app forward; `true` when that worked.
    func open(_ url: URL) async -> Bool
    /// Opens (brings forward) the app at `bundleURL` through Launch Services; `true` when that worked.
    func openApplication(at bundleURL: URL) async -> Bool
    /// Asks the app with `pid` to come forward; `true` when it agreed.
    @discardableResult
    func activate(pid: Int32) -> Bool
}

/// Opens a session's target (1.1 §14.3). Launch Services first: Headroom's panel never activates Headroom, so on
/// macOS 14 and later a plain `activate()` from it may be refused, while `open` and `openApplication` bring the app
/// forward. `activate()` is the fallback.
enum SessionOpening {
    @MainActor
    static func open(_ target: SessionTarget, in workspace: some SessionWorkspace) async {
        switch target {
        case let .link(url, _, fallback):
            if await workspace.open(url) { return }
            if let fallback { await bringForward(fallback, in: workspace) }
        case let .app(app, _):
            await bringForward(app, in: workspace)
        }
    }

    @MainActor
    private static func bringForward(_ app: HostApp, in workspace: some SessionWorkspace) async {
        if let bundleURL = app.bundleURL, await workspace.openApplication(at: bundleURL) { return }
        workspace.activate(pid: app.pid)
    }
}
