import AppKit

/// A menu bar app shows no main menu, but its key equivalents still work while one of its
/// windows is key: ⌘W closes Settings, ⌘Q quits.
enum MainMenu {
    @MainActor
    static func make() -> NSMenu {
        let menu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Headroom", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(submenuItem(appMenu))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(submenuItem(windowMenu))

        return menu
    }

    @MainActor
    private static func submenuItem(_ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = submenu
        return item
    }
}
