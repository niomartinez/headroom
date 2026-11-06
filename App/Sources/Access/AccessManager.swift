import AppKit
import HeadroomModel
import Observation

/// Which folders the app may read, and the paths that point at them (spec §4; 1.1 §3.1, §4.9).
///
/// Unsandboxed (Debug) builds read the standard paths directly. Sandboxed builds need the user to
/// grant each folder once in an open panel; the grants are kept as security-scoped bookmarks and
/// accessed for the app's whole lifetime.
///
/// Also tracks whether the Claude desktop app is installed and whether `~/.claude` exists at all:
/// without them, their folders aren't needed and aren't asked for (spec §2.1, docs/app-store.md §7). Likewise
/// whether Codex is installed (`~/.codex` or the Codex app) for its offer, and whether `~/.copilot` exists.
///
/// The 2 s poll probes the folders off the main thread: `pollCheck()` says what to probe,
/// `SnapshotWorker` runs it, `apply(_:checkedAt:)` takes the answer. User actions (a grant,
/// Settings coming forward) re-probe right away with `refresh(recheckDesktopApp:)`.
@MainActor
@Observable
final class AccessManager {
    let isSandboxed: Bool
    private(set) var paths: ClaudePaths = .standard()
    /// The Codex folder: the grant's URL (`~/.codex` or the user's `CODEX_HOME`), or `~/.codex` unsandboxed.
    private(set) var codexDirectory: URL = HeadroomFolder.codex.expectedURL
    /// The Copilot CLI folder: the grant's URL (`~/.copilot` or the user's `COPILOT_HOME`), or `~/.copilot`
    /// unsandboxed.
    private(set) var copilotDirectory: URL = HeadroomFolder.copilotCLI.expectedURL
    private(set) var state: AccessState = .none
    /// `false` only when `~/.claude` doesn't exist: Claude Code isn't installed (or has never run).
    private(set) var claudeCodeInstalled = true

    private var grants: [HeadroomFolder: BookmarkStore.Grant] = [:]
    /// Looks the Claude app up through Launch Services; runs on the poll's worker.
    @ObservationIgnored let lookUpDesktopApp: @Sendable () -> Bool
    /// Looks the Codex app up through Launch Services; runs on the poll's worker.
    @ObservationIgnored let lookUpCodexApp: @Sendable () -> Bool
    @ObservationIgnored private let bookmarks: BookmarkStore
    @ObservationIgnored private let claudeCodeLocation = HeadroomFolder.claudeCode.expectedURL
    @ObservationIgnored private var desktopAppCheck = PeriodicCheck(interval: ClaudeDesktopApp.recheckInterval)
    @ObservationIgnored private var codexAppCheck = PeriodicCheck(interval: CodexApp.recheckInterval)
    /// Bumped whenever the grants change or access is re-probed here. A poll whose check was made
    /// before that finishes with an out-of-date answer, which is dropped.
    @ObservationIgnored private var generation = 0

    /// `isDesktopAppInstalled` and `isCodexAppInstalled` default to Launch Services lookups of the apps' bundle ids.
    init(
        defaults: UserDefaults = .standard,
        isSandboxed: Bool = Sandbox.isActive(),
        isDesktopAppInstalled: @escaping @Sendable () -> Bool = AccessManager.lookUpDesktopApp,
        isCodexAppInstalled: @escaping @Sendable () -> Bool = AccessManager.lookUpCodexApp
    ) {
        self.isSandboxed = isSandboxed
        self.bookmarks = BookmarkStore(defaults: defaults)
        self.lookUpDesktopApp = isDesktopAppInstalled
        self.lookUpCodexApp = isCodexAppInstalled
    }

    nonisolated static func lookUpDesktopApp() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: ClaudeDesktopApp.bundleIdentifier) != nil
    }

    nonisolated static func lookUpCodexApp() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: CodexApp.bundleIdentifier) != nil
    }

    /// Restores saved grants (sandboxed) and probes the folders. Call once at launch.
    func activate() {
        if isSandboxed {
            for folder in HeadroomFolder.allCases {
                grants[folder] = bookmarks.restore(folder)
            }
            updatePaths()
        }
        refresh()
    }

    /// Re-probes the granted folders now, on the main thread, for user actions whose result must
    /// show at once; polls use `pollCheck()` instead. Folders the sandbox hasn't granted are never
    /// touched, only checked for existence. The desktop and Codex apps are looked up again at most once per
    /// `ClaudeDesktopApp.recheckInterval`, or right away with `recheckDesktopApp`.
    func refresh(recheckDesktopApp: Bool = false) {
        if recheckDesktopApp {
            desktopAppCheck.invalidate()
            codexAppCheck.invalidate()
        }
        generation += 1
        let now = Date()
        apply(check(at: now).run(lookUpDesktopApp: lookUpDesktopApp, lookUpCodexApp: lookUpCodexApp), checkedAt: now)
    }

    /// What a poll should probe, to run off the main thread (`SnapshotWorker`).
    func pollCheck(at now: Date = Date()) -> AccessCheck {
        check(at: now)
    }

    /// `false` when the grants changed or access was re-probed since `result`'s check was made:
    /// the result, and a snapshot built with it, are out of date.
    func isCurrent(_ result: AccessCheck.Result) -> Bool {
        result.generation == generation
    }

    /// Takes a probe's answer (from a poll, checked at `checkedAt`); an out-of-date one is ignored.
    func apply(_ result: AccessCheck.Result, checkedAt: Date) {
        guard isCurrent(result) else { return }
        if let fresh = result.lookedUpDesktopApp {
            desktopAppCheck.record(fresh, at: checkedAt)
        }
        if let fresh = result.lookedUpCodexApp {
            codexAppCheck.record(fresh, at: checkedAt)
        }
        if result.state != state {
            state = result.state
        }
        if result.claudeCodeInstalled != claudeCodeInstalled {
            claudeCodeInstalled = result.claudeCodeInstalled
        }
    }

    func status(of folder: HeadroomFolder) -> FolderStatus {
        if !isGranted(folder) { return .notGranted }
        let readable = switch folder {
        case .claudeCode: state.claudeDirectoryReadable
        case .claudeApp: state.desktopDirectoryReadable
        case .codex: state.codexDirectoryReadable
        case .copilotCLI: state.copilotDirectoryReadable
        }
        return readable ? .readable : .unavailable
    }

    /// Asks, one open panel at a time, for every needed folder that isn't readable: Claude's while Claude is tracked
    /// (the Claude app's folder only while the app is installed, `~/.claude` only once it exists), Codex's while Codex
    /// is tracked and installed. Stops when the user cancels. Unsandboxed builds have nothing to grant and only
    /// re-probe.
    func requestMissingAccess(tracking: ToolTracking = .claudeOnly) {
        refresh(recheckDesktopApp: true)
        let candidates = (tracking.claude ? HeadroomFolder.claude : []) + (tracking.tracksCodex ? [.codex] : [])
        let missing = candidates.filter {
            $0.isNeeded(
                desktopAppInstalled: state.desktopAppInstalled, claudeCodeInstalled: claudeCodeInstalled,
                codexInstalled: state.codexInstalled
            ) && status(of: $0) != .readable
        }
        for folder in missing {
            guard requestAccess(to: folder) else { return }
        }
    }

    /// Whether the sandbox lets Headroom into `folder` (always in unsandboxed builds). Readability is `status(of:)`.
    func hasGrant(_ folder: HeadroomFolder) -> Bool {
        isGranted(folder)
    }

    /// Shows the open panel for `folder` and keeps the grant. Returns `true` when access was granted.
    /// A folder that doesn't exist yet can't be picked (the panel can't enter or create it), so the
    /// user is told what creates it instead. Codex and Copilot CLI also take the folder the user set as the tool's
    /// home (`HeadroomFolder.homeMarkers`); an existing grant of theirs counts as that folder's place.
    @discardableResult
    func requestAccess(to folder: HeadroomFolder) -> Bool {
        let current = grants[folder]?.url
        if current == nil, AccessProbe.isMissing(folder.expectedURL) {
            refresh()
            FolderPicker.showFolderMissing(folder)
            return false
        }
        guard isSandboxed else {
            refresh()
            return status(of: folder) == .readable
        }
        while let chosen = FolderPicker.choose(folder, startingAt: current) {
            guard FolderGrant.isAcceptable(chosen, for: folder, expected: current) else {
                if FolderPicker.retryAfterWrongFolder(chosen, expected: folder) { continue }
                return false
            }
            do {
                try bookmarks.save(chosen, for: folder)
            } catch {
                FolderPicker.showGrantFailed(folder, error: error)
                return false
            }
            grants[folder]?.url.stopAccessingSecurityScopedResource()
            grants[folder] = bookmarks.restore(folder)
            updatePaths()
            refresh()
            return grants[folder] != nil
        }
        return false
    }

    private func check(at now: Date) -> AccessCheck {
        AccessCheck(
            paths: paths,
            claudeGranted: isGranted(.claudeCode),
            desktopGranted: isGranted(.claudeApp),
            claudeCodeLocation: claudeCodeLocation,
            desktopAppInstalled: desktopAppCheck.current(at: now),
            generation: generation,
            tools: AccessCheck.ToolFolders(
                codexDirectory: codexDirectory,
                codexGranted: isGranted(.codex),
                codexLocation: HeadroomFolder.codex.expectedURL,
                codexAppInstalled: codexAppCheck.current(at: now),
                copilotDirectory: copilotDirectory,
                copilotGranted: isGranted(.copilotCLI),
                copilotLocation: HeadroomFolder.copilotCLI.expectedURL
            )
        )
    }

    private func isGranted(_ folder: HeadroomFolder) -> Bool {
        !isSandboxed || grants[folder] != nil
    }

    /// Sandboxed paths follow the granted URLs, so a `~/.claude` that is a symlink still works, and so does a
    /// `CODEX_HOME` or `COPILOT_HOME` elsewhere.
    private func updatePaths() {
        let standard = ClaudePaths.standard()
        let updated = ClaudePaths(
            claudeDirectory: grants[.claudeCode]?.url ?? standard.claudeDirectory,
            desktopSupportDirectory: grants[.claudeApp]?.url ?? standard.desktopSupportDirectory
        )
        if updated != paths {
            paths = updated
        }
        let codex = grants[.codex]?.url ?? HeadroomFolder.codex.expectedURL
        if codex != codexDirectory {
            codexDirectory = codex
        }
        let copilot = grants[.copilotCLI]?.url ?? HeadroomFolder.copilotCLI.expectedURL
        if copilot != copilotDirectory {
            copilotDirectory = copilot
        }
    }
}
