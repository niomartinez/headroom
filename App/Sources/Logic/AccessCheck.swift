import Foundation
import HeadroomModel

/// What one poll asks the file system about Headroom's folders (spec §4; 1.1 §3.1, §4.9). `AccessManager` fills it
/// in on the main actor from its grants; `SnapshotWorker` runs it off the main thread, so a `~/.claude` on a slow or
/// hung mount can't freeze the pill and panel.
struct AccessCheck: Sendable, Equatable {
    var paths: ClaudePaths
    /// Sandboxed builds only probe folders the user granted; unsandboxed builds pass `true`.
    var claudeGranted: Bool
    var desktopGranted: Bool
    /// Where `~/.claude` lives in the real home. Only checked for existence, which needs no grant.
    var claudeCodeLocation: URL
    /// The cached Launch Services answer, or nil when it's due to be looked up again.
    var desktopAppInstalled: Bool?
    /// `AccessManager`'s generation when the check was made; a result for an older generation
    /// (grants changed, or the user re-checked, while it ran) is dropped.
    var generation: Int
    /// The Codex and Copilot CLI folders. Nil checks neither: their `AccessState` fields stay false.
    var tools: ToolFolders? = nil

    /// The Codex and Copilot CLI folders (1.1 §3.1, §4.9).
    struct ToolFolders: Sendable, Equatable {
        /// The granted Codex folder (`~/.codex` or the user's `CODEX_HOME`).
        var codexDirectory: URL
        var codexGranted: Bool
        /// Where `~/.codex` lives in the real home: only checked for existence ("Codex installed").
        var codexLocation: URL
        /// The cached Launch Services answer for the Codex app, or nil when it's due to be looked up again.
        var codexAppInstalled: Bool?
        /// The granted Copilot CLI folder (`~/.copilot` or the user's `COPILOT_HOME`).
        var copilotDirectory: URL
        var copilotGranted: Bool
        /// Where `~/.copilot` lives in the real home: only checked for existence ("Copilot CLI installed").
        var copilotLocation: URL
    }

    struct Result: Sendable, Equatable {
        var state: AccessState
        /// `false` only when `~/.claude` doesn't exist at all: Claude Code isn't installed (or has
        /// never run), so there is nothing to grant.
        var claudeCodeInstalled: Bool
        /// The fresh Launch Services answer when one was looked up, for `AccessManager` to cache.
        var lookedUpDesktopApp: Bool?
        var generation: Int
        /// The fresh Launch Services answer for the Codex app when one was looked up.
        var lookedUpCodexApp: Bool? = nil

        /// HeadroomStore reports `~/.claude` as unavailable whenever it can't be read. Without the
        /// folder there is nothing to grant: the panel would show a "Give access" prompt that can
        /// never succeed instead of its empty state (docs/app-store.md §7), so drop the issue, the
        /// way a missing Claude desktop app drops `desktopFolderUnavailable`. The same goes for Codex's folder while
        /// Codex isn't installed.
        func adjusting(_ snapshot: HeadroomSnapshot) -> HeadroomSnapshot {
            var adjusted = snapshot
            if !claudeCodeInstalled {
                adjusted.issues.remove(.claudeCodeFolderUnavailable)
            }
            if !state.codexInstalled, adjusted.issues.contains(.codexFolderUnavailable) {
                adjusted.issues.remove(.codexFolderUnavailable)
            }
            return adjusted
        }
    }

    /// Probes the granted folders (never the others) and whether `~/.claude`, `~/.codex` and `~/.copilot` exist, and
    /// looks the Claude and Codex apps up when that's due.
    func run(lookUpDesktopApp: () -> Bool, lookUpCodexApp: () -> Bool = { false }) -> Result {
        let lookedUp = desktopAppInstalled == nil ? lookUpDesktopApp() : nil
        var state = AccessState(
            claudeDirectoryReadable: claudeGranted && AccessProbe.isReadableDirectory(paths.claudeDirectory),
            desktopDirectoryReadable: desktopGranted && AccessProbe.isReadableDirectory(paths.desktopSupportDirectory),
            desktopAppInstalled: desktopAppInstalled ?? lookedUp ?? false
        )
        var lookedUpCodexApp: Bool?
        if let tools {
            if tools.codexAppInstalled == nil { lookedUpCodexApp = lookUpCodexApp() }
            state.codexDirectoryReadable = tools.codexGranted && AccessProbe.isReadableDirectory(tools.codexDirectory)
            state.codexInstalled = state.codexDirectoryReadable || (tools.codexAppInstalled ?? lookedUpCodexApp ?? false)
                || !AccessProbe.isMissing(tools.codexLocation)
            state.copilotDirectoryReadable = tools.copilotGranted
                && AccessProbe.isReadableDirectory(tools.copilotDirectory)
            state.copilotCLIInstalled = state.copilotDirectoryReadable || !AccessProbe.isMissing(tools.copilotLocation)
        }
        let claudeCodeInstalled = state.claudeDirectoryReadable || !AccessProbe.isMissing(claudeCodeLocation)
        return Result(
            state: state, claudeCodeInstalled: claudeCodeInstalled, lookedUpDesktopApp: lookedUp, generation: generation,
            lookedUpCodexApp: lookedUpCodexApp
        )
    }
}
