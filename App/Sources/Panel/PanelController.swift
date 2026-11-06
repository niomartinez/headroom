import AppKit
import HeadroomModel
import HeadroomUI

/// Shows `PanelView` right-aligned under the pill (spec §1.2). Closes on a click outside, Esc,
/// when Headroom resigns active, when another app becomes active, or when the screen
/// configuration changes, and follows the content's height while open.
@MainActor
final class PanelController {
    /// Called when the panel opens or closes, to highlight the status item.
    var onVisibilityChange: ((Bool) -> Void)?

    private static let escapeKeyCode: UInt16 = 53 // kVK_Escape

    private let model: AppModel
    private let panel = PanelWindow.make()
    private let hostingView: PanelHostingView
    private var actions: PanelActions = .none
    /// The status item button the panel hangs from; its frame is read live, since the pill
    /// changes width with moments.
    private weak var anchorButton: NSStatusBarButton?
    private var eventMonitors: [Any] = []
    /// Notification observers installed while the panel is open, with the center each belongs to.
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var layoutPending = false
    /// The panel gets a new snapshot only when what it draws changed.
    private var drawn = ChangeGate<PanelDrawKey>()

    init(model: AppModel, actions: PanelActions) {
        self.model = model
        hostingView = PanelHostingView(rootView: PanelHost(snapshot: model.snapshot, now: model.now, actions: .none))
        hostingView.sizingOptions = [.intrinsicContentSize]
        // Below the window's "stay put" priority (500) so AppKit never resizes the panel on its
        // own; above the fitting-size compression (50) so `fittingSize` still measures the content.
        for orientation in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            hostingView.setContentHuggingPriority(.init(400), for: orientation)
            hostingView.setContentCompressionResistancePriority(.init(400), for: orientation)
        }
        panel.contentView = hostingView
        self.actions = closingFirst(actions)
        hostingView.onIntrinsicSizeChange = { [weak self] in
            self?.scheduleLayout()
        }
        observeContinuously { [weak self] in
            self?.modelChanged()
        }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(from button: NSStatusBarButton) {
        if panel.isVisible {
            close()
        } else {
            show(from: button)
        }
    }

    func show(from button: NSStatusBarButton) {
        guard button.window != nil else { return }
        anchorButton = button
        // Before drawing: what was unseen until now gets the wash, and counts as seen from here (1.1 §14.4).
        model.panelOpened()
        push(content(resolvingTargets: true))
        setKeyboardNavigation(false)
        layout()
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
        onVisibilityChange?(true)
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        removeMonitors()
        model.panelClosed()
        onVisibilityChange?(false)
    }

    // MARK: Content

    /// Runs after every poll. A closed panel is left alone; `show` catches it up.
    private func modelChanged() {
        // Read before the visibility check, so observation keeps tracking all of it; where rows open is only looked
        // up for an open panel.
        let isVisible = panel.isVisible
        let content = content(resolvingTargets: isVisible)
        guard isVisible else { return }
        push(content)
    }

    /// What the panel draws now: the snapshot with dismissed waits read as idle, the needs-you marks (1.1 §14.4) and
    /// where each row opens (§14.3), unless `resolvingTargets` is false.
    private func content(resolvingTargets: Bool) -> PanelHost {
        let presentation = model.presentation
        let snapshot = presentation.snapshot
        var openTitles: [String: String] = [:]
        if resolvingTargets {
            for session in snapshot.sessions {
                openTitles[session.id] = actions.sessionOpenTitle(session.id)
            }
        }
        return PanelHost(
            snapshot: snapshot, now: model.now, actions: actions, sampleData: model.panelSampleData,
            tool: model.ringsChoice.tool, showsCodexOffer: model.showsCodexOffer, unseenIDs: model.needsYou.panelUnseenIDs,
            dismissedIDs: presentation.dismissedIDs, finishedIDs: model.panelFinishedIDs, openTitles: openTitles,
            keyboardNavigation: hostingView.rootView.keyboardNavigation
        )
    }

    private func push(_ content: PanelHost) {
        let key = PanelDrawKey(
            snapshot: content.snapshot, now: content.now, sampleData: content.sampleData, tool: content.tool,
            showsCodexOffer: content.showsCodexOffer, unseenIDs: content.unseenIDs, dismissedIDs: content.dismissedIDs,
            finishedIDs: content.finishedIDs, openTitles: content.openTitles
        )
        guard drawn.admit(key) else { return }
        hostingView.rootView = content
    }

    private func setKeyboardNavigation(_ enabled: Bool) {
        guard hostingView.rootView.keyboardNavigation != enabled else { return }
        hostingView.rootView.keyboardNavigation = enabled
    }

    // MARK: Layout

    /// The status item button's window and its frame in screen coordinates.
    private var anchor: (window: NSWindow, rect: CGRect)? {
        guard let button = anchorButton, let window = button.window else { return nil }
        return (window, window.convertToScreen(button.convert(button.bounds, to: nil)))
    }

    private func layout() {
        guard let anchor, let visibleFrame = (anchor.window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let frame = PanelPlacement.frame(contentSize: hostingView.fittingSize, below: anchor.rect, in: visibleFrame)
        if frame != panel.frame {
            panel.setFrame(frame, display: true)
        }
        // The shadow follows PanelView's rounded shape, drawn on a clear window.
        panel.invalidateShadow()
    }

    /// Coalesces size changes into one layout on the next main-actor turn (never mid-layout).
    private func scheduleLayout() {
        guard panel.isVisible, !layoutPending else { return }
        layoutPending = true
        Task { [weak self] in
            guard let self else { return }
            self.layoutPending = false
            self.layout()
        }
    }

    // MARK: Closing

    /// Every panel action that opens something closes the panel before it runs (Settings, alerts,
    /// open panels, quit, a session's app). Turning sample data on or off, declining the Codex offer, and dismissing a
    /// wait (or undoing that) keep it open, to show the change.
    private func closingFirst(_ actions: PanelActions) -> PanelActions {
        PanelActions(
            openSettings: { [weak self] in self?.close(); actions.openSettings() },
            openToolsSettings: { [weak self] in self?.close(); actions.openToolsSettings() },
            connectTerminal: { [weak self] in self?.close(); actions.connectTerminal() },
            disconnectTerminal: { [weak self] in self?.close(); actions.disconnectTerminal() },
            grantAccess: { [weak self] in self?.close(); actions.grantAccess() },
            refresh: actions.refresh,
            quit: { [weak self] in self?.close(); actions.quit() },
            showSampleData: actions.showSampleData,
            hideSampleData: actions.hideSampleData,
            giveCodexAccess: { [weak self] in self?.close(); actions.giveCodexAccess() },
            declineCodex: actions.declineCodex,
            reconnectGitHub: { [weak self] in self?.close(); actions.reconnectGitHub() },
            sessionOpenTitle: actions.sessionOpenTitle,
            openSession: { [weak self] id in self?.close(); actions.openSession(id) },
            dismissSession: actions.dismissSession,
            undoDismiss: actions.undoDismiss,
            clearFinished: actions.clearFinished
        )
    }

    private func installMonitors() {
        removeMonitors()
        let mouseDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Clicks in other apps, including other menu bar items.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleOutsideClick(event) }
        }) {
            eventMonitors.append(monitor)
        }
        // Clicks in Headroom's other windows, and Esc.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mouseDown.union(.keyDown), handler: { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handleLocalEvent(event) ?? false }
            return consumed ? nil : event
        }) {
            eventMonitors.append(monitor)
        }
        observe(NotificationCenter.default, NSApplication.didResignActiveNotification) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        // Cmd-Tab, the Dock or Spotlight bring another app forward without a click.
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didActivateApplicationNotification) { [weak self] notification in
            let app = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
                .map { (pid: $0.processIdentifier, isRegularApp: $0.activationPolicy == .regular) }
            MainActor.assumeIsolated {
                if PanelDismissal.closesOnActivation(of: app, ownPID: ProcessInfo.processInfo.processIdentifier) {
                    self?.close()
                }
            }
        }
        // A display added, removed or rearranged moves the menu bar out from under the panel.
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    /// Delivered on the main queue.
    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        _ handler: @escaping @Sendable (Notification) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main, using: handler)
        observers.append((center, token))
    }

    private func removeMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers.removeAll()
    }

    /// Returns `true` when the event is consumed.
    private func handleLocalEvent(_ event: NSEvent) -> Bool {
        if event.type == .keyDown {
            if [48, 123, 124, 125, 126].contains(event.keyCode) {
                setKeyboardNavigation(true)
            }
            guard event.keyCode == Self.escapeKeyCode else { return false }
            close()
            return true
        }
        if event.window === panel { setKeyboardNavigation(false) }
        if event.window !== panel && event.window !== anchor?.window {
            handleOutsideClick(event)
        }
        return false
    }

    /// Clicks on the pill itself toggle the panel through the button's action, so they're ignored
    /// here. On macOS 26 the menu bar item's window belongs to Control Center, so those clicks can
    /// also reach the global monitor as clicks "in another app".
    private func handleOutsideClick(_ event: NSEvent) {
        let location = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
        if anchor?.rect.contains(location) == true { return }
        close()
    }
}
