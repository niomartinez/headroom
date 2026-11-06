import AppKit
import Observation
import SwiftUI

/// The Settings window (spec §1.3), created on first use and reused afterwards. Also shown
/// automatically on first launch as onboarding.
///
/// Whenever the window becomes key, Launch at login re-reads its status (the user may have changed
/// it in System Settings › Login Items meanwhile) and `onBecomeKey` runs.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let makeView: (@escaping () -> Void) -> SettingsView
    private let launchAtLogin: LaunchAtLogin
    private let navigation: SettingsNavigation
    private let onBecomeKey: () -> Void
    private var window: NSWindow?

    init(
        launchAtLogin: LaunchAtLogin,
        navigation: SettingsNavigation,
        onBecomeKey: @escaping () -> Void = {},
        makeView: @escaping (@escaping () -> Void) -> SettingsView
    ) {
        self.launchAtLogin = launchAtLogin
        self.navigation = navigation
        self.onBecomeKey = onBecomeKey
        self.makeView = makeView
    }

    /// Shows the window on `tab`, or on the tab last shown.
    func show(tab: SettingsTab? = nil) {
        if let tab {
            navigation.select(tab)
        }
        let window = window ?? makeWindow()
        self.window = window
        // Already key (e.g. reopened from Finder while in front): no didBecomeKey follows.
        if window.isKeyWindow {
            refreshForFocus()
        }
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        navigation.beginOnboarding()
        show()
    }

    func windowWillClose(_ notification: Notification) {
        // Closing is an explicit skip; opening the window alone never completes setup.
        navigation.finishOnboarding()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshForFocus()
    }

    private func refreshForFocus() {
        launchAtLogin.refresh()
        onBecomeKey()
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: makeView { [weak self] in self?.window?.close() })
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.title = "Headroom Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self
        window.center()
        return window
    }
}
