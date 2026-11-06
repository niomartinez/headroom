import AppKit
import HeadroomModel
import SessionKit

/// Clicking a session row opens it (1.1 §14.3): the Claude app's own session, the Codex app's thread, or the terminal
/// or editor a CLI session runs in, brought forward. No new entitlements: Launch Services and `sysctl` only, no Apple
/// Events. Never in sample data. Never logs session ids or names.
@MainActor
final class SessionOpener {
    private let model: AppModel
    private let workspace = SystemSessionWorkspace()
    private lazy var resolver = SessionTargetResolver(
        processes: SystemProcessTable(),
        appForPID: { NSRunningApplication(processIdentifier: $0).map(HostApp.init) },
        runningApp: { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first.map(HostApp.init) },
        handlerName: Self.handlerName
    )
    /// Targets resolved while the panel is open, per session and what they were resolved from; `reset()` on close.
    private var cache: [String: (key: CacheKey, target: SessionTarget?)] = [:]
    /// `hostBundleID(for:)`'s answers, per session and what they were resolved from; kept while the panel is closed.
    private var hostCache: [String: (key: CacheKey, bundleID: String?)] = [:]
    static let copilotAppBundleID = "com.github.githubapp"

    private struct CacheKey: Equatable {
        var pid: Int32?
        var desktopSessionID: String?
        var origin: SessionOrigin

        init(_ session: SessionInfo) {
            pid = session.pid
            desktopSessionID = session.desktopSessionID
            origin = session.origin
        }
    }

    init(model: AppModel) {
        self.model = model
    }

    /// The row's hover label and tooltip start ("Open in Claude", "Show in Terminal"); nil when the row isn't a button.
    /// The panel asks for every row as it opens: the first question resolves all the rows not cached yet in one pass,
    /// which reads the process list and asks Launch Services at most once.
    func title(for id: String) -> String? {
        guard !model.sampleData.isOn, let session = session(id) else { return nil }
        if let cached = cache[id], cached.key == CacheKey(session) {
            return cached.target?.title
        }
        let unresolved = model.snapshot.sessions.filter { cache[$0.id]?.key != CacheKey($0) }
        let targets = resolver.targets(for: unresolved, sampleData: false)
        for session in unresolved {
            cache[session.id] = (CacheKey(session), targets[session.id])
        }
        return targets[id]?.title
    }

    /// A click on the row. The panel has closed by now (`PanelController`); the target is looked up again, since the
    /// session's app may have changed since the panel drew it.
    func open(id: String) {
        guard !model.sampleData.isOn, let session = session(id),
              let target = resolver.target(for: session, sampleData: false)
        else { return }
        let workspace = workspace
        Task {
            await SessionOpening.open(target, in: workspace)
        }
    }

    /// The app a just-finished session runs in, for "looked at it there" (1.1.2): its terminal or editor, the Claude
    /// or Codex app, or the Copilot app. Resolved once per session and process.
    func hostBundleID(for session: SessionInfo) -> String? {
        if let cached = hostCache[session.id], cached.key == CacheKey(session) { return cached.bundleID }
        let bundleID: String?
        if session.tool == .copilot, session.origin == .desktop {
            bundleID = Self.copilotAppBundleID
        } else {
            switch resolver.target(for: session, sampleData: false) {
            case let .app(app, _)?: bundleID = app.bundleIdentifier
            case let .link(_, _, fallback)?: bundleID = fallback?.bundleIdentifier
            case nil: bundleID = nil
            }
        }
        if hostCache.count > 200 { hostCache.removeAll() }
        hostCache[session.id] = (CacheKey(session), bundleID)
        return bundleID
    }

    /// The panel closed: the next one resolves every row again.
    func reset() {
        cache.removeAll()
    }

    private func session(_ id: String) -> SessionInfo? {
        model.snapshot.sessions.first { $0.id == id }
    }

    /// The display name of the app Launch Services opens `url` with ("ChatGPT" for `codex://`).
    private nonisolated static func handlerName(_ url: URL) -> String? {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return nil }
        let bundle = Bundle(url: app)
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        return name?.isEmpty == false ? name : app.deletingPathExtension().lastPathComponent
    }
}

extension HostApp {
    init(_ app: NSRunningApplication) {
        self.init(
            pid: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            name: HostAppNames.name(bundleIdentifier: app.bundleIdentifier, localizedName: app.localizedName),
            bundleURL: app.bundleURL,
            isRegular: app.activationPolicy == .regular
        )
    }
}

/// `NSWorkspace` for `SessionOpening`: activate, and keep the links out of Recent Items.
@MainActor
struct SystemSessionWorkspace: SessionWorkspace {
    func open(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.open(url, configuration: Self.configuration()) { _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    func openApplication(at bundleURL: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: Self.configuration()) { _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    @discardableResult
    func activate(pid: Int32) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.activate() ?? false
    }

    private static func configuration() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        return configuration
    }
}
