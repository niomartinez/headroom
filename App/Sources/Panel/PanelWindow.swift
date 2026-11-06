import AppKit

/// The borderless, non-activating panel that drops below the pill (spec §1.2). It can become key
/// (for Esc) without activating Headroom, so the user's app keeps focus.
final class PanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    static func make() -> PanelWindow {
        let panel = PanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .utilityWindow
        // PanelView is always dark (spec §1.2); keep system controls inside it dark too.
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }
}
