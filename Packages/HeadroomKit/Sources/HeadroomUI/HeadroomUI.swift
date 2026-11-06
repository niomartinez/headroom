import SwiftUI

/// Actions the panel can trigger; the app supplies them.
public struct PanelActions {
    public var openSettings: @MainActor () -> Void
    /// "Settings…" next to "Connect GitHub in Settings" (1.1 §4.6): Settings on its Tools tab. Defaults to
    /// `openSettings`.
    public var openToolsSettings: @MainActor () -> Void
    public var connectTerminal: @MainActor () -> Void
    public var disconnectTerminal: @MainActor () -> Void
    public var grantAccess: @MainActor () -> Void
    /// The footer's Refresh button: read everything again now instead of waiting for the next poll.
    public var refresh: @MainActor () -> Void
    public var quit: @MainActor () -> Void
    /// "Preview with sample data" in the empty panel.
    public var showSampleData: @MainActor () -> Void
    /// "Turn off" in the footer while sample data shows.
    public var hideSampleData: @MainActor () -> Void
    /// "Give access" in the Codex offer (1.1 §6.3): the folder picker, then `trackCodex = true` on success.
    public var giveCodexAccess: @MainActor () -> Void
    /// "Not now" in the Codex offer: `trackCodex = false`.
    public var declineCodex: @MainActor () -> Void
    /// "Reconnect" next to "Sign-in expired" (1.1 §4.6): the Connect GitHub sheet.
    public var reconnectGitHub: @MainActor () -> Void
    /// Where a click on a session row goes (1.1 §14.3): "Open in Claude", "Open in ChatGPT", "Show in Terminal"; nil
    /// when Headroom can't tell where the session runs, or in sample data (the row is then not a button).
    public var sessionOpenTitle: @MainActor (_ sessionID: String) -> String?
    /// A click on an openable row: closes the panel, then opens the session (or brings its app forward).
    public var openSession: @MainActor (_ sessionID: String) -> Void
    /// "Dismiss" on a Needs you row (1.1 §14.4): this waiting episode stops counting.
    public var dismissSession: @MainActor (_ sessionID: String) -> Void
    /// "Show in Needs you again" on a dismissed row.
    public var undoDismiss: @MainActor (_ sessionID: String) -> Void
    /// "Clear" on Just finished (1.1.1): every finished session moves to Idle.
    public var clearFinished: @MainActor () -> Void

    public init(
        openSettings: @escaping @MainActor () -> Void = {},
        openToolsSettings: (@MainActor () -> Void)? = nil,
        connectTerminal: @escaping @MainActor () -> Void = {},
        disconnectTerminal: @escaping @MainActor () -> Void = {},
        grantAccess: @escaping @MainActor () -> Void = {},
        refresh: @escaping @MainActor () -> Void = {},
        quit: @escaping @MainActor () -> Void = {},
        showSampleData: @escaping @MainActor () -> Void = {},
        hideSampleData: @escaping @MainActor () -> Void = {},
        giveCodexAccess: @escaping @MainActor () -> Void = {},
        declineCodex: @escaping @MainActor () -> Void = {},
        reconnectGitHub: @escaping @MainActor () -> Void = {},
        sessionOpenTitle: @escaping @MainActor (_ sessionID: String) -> String? = { _ in nil },
        openSession: @escaping @MainActor (_ sessionID: String) -> Void = { _ in },
        dismissSession: @escaping @MainActor (_ sessionID: String) -> Void = { _ in },
        undoDismiss: @escaping @MainActor (_ sessionID: String) -> Void = { _ in },
        clearFinished: @escaping @MainActor () -> Void = {}
    ) {
        self.openSettings = openSettings
        self.openToolsSettings = openToolsSettings ?? openSettings
        self.connectTerminal = connectTerminal
        self.disconnectTerminal = disconnectTerminal
        self.grantAccess = grantAccess
        self.refresh = refresh
        self.quit = quit
        self.showSampleData = showSampleData
        self.hideSampleData = hideSampleData
        self.giveCodexAccess = giveCodexAccess
        self.declineCodex = declineCodex
        self.reconnectGitHub = reconnectGitHub
        self.sessionOpenTitle = sessionOpenTitle
        self.openSession = openSession
        self.dismissSession = dismissSession
        self.undoDismiss = undoDismiss
        self.clearFinished = clearFinished
    }

    /// The action behind a tool status line's button ("Settings…", "Reconnect").
    @MainActor func perform(_ action: ToolStatusLine.Action) {
        switch action {
        case .openToolsSettings: openToolsSettings()
        case .reconnectGitHub: reconnectGitHub()
        }
    }

    public static var none: PanelActions { PanelActions() }
}

/// Sample data mode as the panel shows it: made-up sessions and limits for App Review, demos and
/// Macs without Claude data. The app decides which applies (`SampleDataMode`).
public enum PanelSampleData: Sendable, Equatable {
    /// Real data; nothing about sample data.
    case hidden
    /// No Claude data found at all: the empty state offers "Preview with sample data".
    case offered
    /// Sample data is showing: the footer reads "Sample data · Turn off".
    case showing
}
