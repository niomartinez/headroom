import CodexKit
import Darwin
import Foundation
import HeadroomModel
import HeadroomStore
import SessionKit
import SetupKit

/// Runs all file I/O off the main thread: the access probe, the snapshot build and the bridge
/// states. `SnapshotBuilder` is not thread-safe; the actor makes sure only one build runs at a time
/// and keeps its caches between polls (spec §4). Being serial, it also keeps at most one probe
/// blocked on a hung mount under `~/.claude`, while the pill and panel stay responsive.
actor SnapshotWorker {
    struct Result: Sendable {
        let snapshot: HeadroomSnapshot
        /// nil when `~/.claude` isn't readable (or Claude isn't tracked), so the bridge state can't be known.
        let bridgeState: BridgeInstallState?
        /// `bridgeState` is `.notInstalled`, yet `~/.claude/headroom` or a copy of it that
        /// Disconnect was deleting is still on disk: a Disconnect that didn't finish. Disconnect
        /// deletes them, so Settings offers it again.
        let hasBridgeLeftovers: Bool
        /// The Claude app's account that `snapshot`'s desktop readings belong to
        /// (`SnapshotBuilder.desktopAccount`), so moments can tell an account switch from a limit
        /// crossing. nil without desktop samples.
        let desktopAccount: String?
        /// What this poll's access check found; the snapshot was built with `access.state`.
        let access: AccessCheck.Result
        /// Connect Copilot CLI's state (1.1 §4.9); nil while the Copilot CLI folder isn't readable, or in a build
        /// without Copilot CLI support.
        let copilotCLIState: CopilotCLIState?
        /// `copilotCLIState` is `.notInstalled`, yet `~/.copilot/headroom` or a copy an earlier Disconnect was
        /// deleting is still there; Disconnect deletes them.
        let hasCopilotCLILeftovers: Bool
        /// The sources the snapshot was built from: moments aren't compared across a change (a tool just tracked
        /// brings its sessions and limits all at once).
        let sources: SourceSelection
        /// Which sessions the user looked at in the Claude and Codex apps (1.1.2, §14.15); nil when no just-finished
        /// session needs them.
        var views: SessionViewSignals? = nil
    }

    private var builder: SnapshotBuilder?
    /// Kept while the paths are unchanged, with its caches.
    private var viewReader: (paths: ClaudePaths, codex: URL?, reader: SessionViewReader)?
    /// NSWorkspace's answer for the Codex app, which the package can't ask (1.1 §3.5).
    private let codexAppIsRunning: @Sendable () -> Bool
    #if HEADROOM_COPILOT_CLI
    /// The last Copilot CLI state, kept while the hooks file and the script are unchanged: the 2 s poll reads them
    /// only when they change.
    private var copilotCLICache: (stamp: CopilotCLIStamp, state: CopilotCLIState)?
    #endif

    /// `codexAppIsRunning`: whether the Codex app (`com.openai.codex`) runs; the process list covers the CLI.
    init(codexAppIsRunning: @escaping @Sendable () -> Bool = { false }) {
        self.codexAppIsRunning = codexAppIsRunning
    }

    /// `lookUpDesktopApp` and `lookUpCodexApp` run here, off the main thread, when `check` says a lookup is due.
    /// `tracking` picks the tools (1.1 §7); `copilot` is `CopilotService`'s usage, used while Copilot is tracked.
    /// `finishedIDs`: the sessions in Just finished, whose viewing signals are read (1.1.2).
    func refresh(
        check: AccessCheck,
        tracking: ToolTracking = .claudeOnly,
        copilot: ToolUsage? = nil,
        finishedIDs: Set<String> = [],
        lookUpDesktopApp: @Sendable () -> Bool,
        lookUpCodexApp: @Sendable () -> Bool = { false },
        now: Date
    ) -> Result {
        let access = check.run(lookUpDesktopApp: lookUpDesktopApp, lookUpCodexApp: lookUpCodexApp)
        let copilotCLI = copilotCLIState(check: check, access: access.state)
        let sources = SourceSelection(
            claude: tracking.claude,
            codex: tracking.tracksCodex,
            copilotCLI: tracking.copilot && (copilotCLI.state?.isConnected ?? false),
            codexHome: check.tools?.codexDirectory,
            copilotCLIHome: check.tools?.copilotDirectory
        )
        let builder = reusableBuilder(for: check.paths)
        let built = builder.build(access: access.state, sources: sources, copilot: tracking.copilot ? copilot : nil, now: now)
        let snapshot = access.adjusting(built)
        // Read right after the build that made the snapshot: it belongs to that build.
        let desktopAccount = builder.desktopAccount
        // The builder's cached state: settings.json is parsed again only when it or bridge.sh
        // change, not on every poll. nil when ~/.claude wasn't readable.
        let bridgeState = builder.bridgeInstallState
        // One lstat and a listing of ~/.claude's top level, and only while nothing is connected.
        let hasBridgeLeftovers = access.state.claudeDirectoryReadable && bridgeState == .notInstalled
            && BridgeInstaller(claudeDirectory: check.paths.claudeDirectory).hasLeftoverFiles()
        return Result(
            snapshot: snapshot,
            bridgeState: bridgeState,
            hasBridgeLeftovers: hasBridgeLeftovers,
            desktopAccount: desktopAccount,
            access: access,
            copilotCLIState: copilotCLI.state,
            hasCopilotCLILeftovers: copilotCLI.leftovers,
            sources: sources,
            views: viewSignals(snapshot: snapshot, finishedIDs: finishedIDs, check: check, access: access.state)
        )
    }

    /// Only while a just-finished Claude app session or Codex app thread needs them: the head of every listed Claude
    /// app session's file (which one is on screen), and the Codex app's unread threads.
    private func viewSignals(
        snapshot: HeadroomSnapshot, finishedIDs: Set<String>, check: AccessCheck, access: AccessState
    ) -> SessionViewSignals? {
        let finished = snapshot.sessions.filter { finishedIDs.contains($0.id) && $0.activity == .idle && $0.origin == .desktop }
        let claude = access.desktopDirectoryReadable && finished.contains { $0.tool == .claude && $0.desktopSessionID != nil }
        let codex = access.codexDirectoryReadable && finished.contains { $0.tool == .codex }
        guard claude || codex else { return nil }
        let codexDirectory = check.tools?.codexDirectory
        let reader: SessionViewReader
        if let viewReader, viewReader.paths == check.paths, viewReader.codex == codexDirectory {
            reader = viewReader.reader
        } else {
            reader = SessionViewReader(paths: check.paths, codex: codexDirectory.map(CodexPaths.init(codexDirectory:)))
            viewReader = (check.paths, codexDirectory, reader)
        }
        let claudeIDs = claude
            ? Set(snapshot.sessions.compactMap { $0.tool == .claude && $0.origin == .desktop ? $0.desktopSessionID : nil })
            : []
        return reader.read(claudeDesktopIDs: claudeIDs, codex: codex)
    }

    func installBridge(claudeDirectory: URL) throws {
        try BridgeInstaller(claudeDirectory: claudeDirectory).install()
    }

    func uninstallBridge(claudeDirectory: URL) throws {
        try BridgeInstaller(claudeDirectory: claudeDirectory).uninstall()
    }

    /// A new grant can change the paths; the builder's caches belong to the old ones.
    private func reusableBuilder(for paths: ClaudePaths) -> SnapshotBuilder {
        if let builder, builder.paths == paths {
            return builder
        }
        let fresh = SnapshotBuilder(
            paths: paths,
            probe: SystemProcessProbe(),
            codexRuntime: CodexRuntimeProbe(appIsRunning: codexAppIsRunning)
        )
        builder = fresh
        return fresh
    }

    // MARK: Copilot CLI (1.1 §4.9)

    /// Connect Copilot CLI's state while the folder is readable, and whether a Disconnect left files behind (one
    /// lstat and a listing of the folder's top level, only while nothing is connected).
    private func copilotCLIState(check: AccessCheck, access: AccessState) -> (state: CopilotCLIState?, leftovers: Bool) {
        #if HEADROOM_COPILOT_CLI
        guard access.copilotDirectoryReadable, let directory = check.tools?.copilotDirectory else {
            copilotCLICache = nil
            return (nil, false)
        }
        let installer = CopilotBridgeInstaller(copilotDirectory: directory)
        let stamp = CopilotCLIStamp(installer: installer)
        let state: CopilotCLIState
        if let cached = copilotCLICache, cached.stamp == stamp {
            state = cached.state
        } else {
            state = CopilotCLIState(installer.state())
            copilotCLICache = (stamp, state)
        }
        return (state, state == .notInstalled && installer.hasLeftoverFiles())
        #else
        return (nil, false)
        #endif
    }

    #if HEADROOM_COPILOT_CLI
    /// What Connect Copilot CLI would change now, for its confirmation dialog.
    func copilotCLIInstallPlan(copilotDirectory: URL) -> [CopilotCLIConsent.Change] {
        CopilotBridgeInstaller(copilotDirectory: copilotDirectory).installPlan().map(CopilotCLIConsent.Change.init)
    }

    /// What Disconnect would remove now.
    func copilotCLIUninstallPlan(copilotDirectory: URL) -> [CopilotCLIConsent.Change] {
        CopilotBridgeInstaller(copilotDirectory: copilotDirectory).uninstallPlan().map(CopilotCLIConsent.Change.init)
    }

    func installCopilotCLI(copilotDirectory: URL) throws {
        copilotCLICache = nil
        try CopilotBridgeInstaller(copilotDirectory: copilotDirectory).install()
    }

    func uninstallCopilotCLI(copilotDirectory: URL) throws {
        copilotCLICache = nil
        try CopilotBridgeInstaller(copilotDirectory: copilotDirectory).uninstall()
    }
    #endif
}

#if HEADROOM_COPILOT_CLI
extension CopilotCLIState {
    init(_ state: CopilotBridgeState) {
        switch state {
        case .notInstalled: self = .notInstalled
        case .installed: self = .installed
        case .outdated: self = .outdated
        case let .unreadable(reason): self = .unreadable(reason)
        }
    }
}

extension CopilotCLIConsent.Change {
    init(_ change: CopilotBridgeChange) {
        let verb = switch change.action {
        case .create: "Create"
        case .replace: "Replace"
        case .remove: "Remove"
        }
        self.init(verb: verb, path: change.path, detail: change.detail)
    }
}

/// The files `CopilotBridgeInstaller.state()` reads: while neither changes (inode, size, modification time), neither
/// does the state.
struct CopilotCLIStamp: Equatable {
    struct FileStamp: Equatable {
        var inode: UInt64
        var size: Int64
        var modified: timespec

        static func == (lhs: FileStamp, rhs: FileStamp) -> Bool {
            lhs.inode == rhs.inode && lhs.size == rhs.size
                && lhs.modified.tv_sec == rhs.modified.tv_sec && lhs.modified.tv_nsec == rhs.modified.tv_nsec
        }
    }

    var directory: String
    var hooks: FileStamp?
    var script: FileStamp?

    init(installer: CopilotBridgeInstaller) {
        directory = installer.paths.copilotDirectory.standardizedFileURL.path
        hooks = Self.stamp(installer.paths.hooksFile)
        script = Self.stamp(installer.paths.bridgeScriptFile)
    }

    /// `lstat`, so a link swapped for another counts as a change; nil when nothing is there.
    private static func stamp(_ url: URL) -> FileStamp? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return FileStamp(inode: UInt64(info.st_ino), size: Int64(info.st_size), modified: info.st_mtimespec)
    }
}
#endif
