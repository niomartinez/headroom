import AppKit

/// The open panel and alerts used to grant folder access in sandboxed builds (spec §4).
@MainActor
enum FolderPicker {
    /// Shows an open panel already inside `folder` (or `startingAt`, an earlier grant elsewhere), hidden files
    /// visible, so the user only has to click Grant Access. Returns the chosen folder, or nil when cancelled.
    static func choose(_ folder: HeadroomFolder, startingAt start: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Grant Access to the \(folder.title)"
        panel.message = folder.openPanelMessage
        panel.prompt = "Grant Access"
        panel.directoryURL = start ?? folder.expectedURL
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.resolvesAliases = true
        NSApplication.shared.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Returns `true` when the user wants to pick again.
    static func retryAfterWrongFolder(_ chosen: URL, expected folder: HeadroomFolder) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "That's not the \(folder.title)"
        alert.informativeText = "You chose “\(chosen.lastPathComponent)”. \(folder.wrongFolderMessage)"
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// The folder doesn't exist yet, so there is nothing to pick.
    static func showFolderMissing(_ folder: HeadroomFolder) {
        NSApplication.shared.activate()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "\(folder.displayPath) doesn't exist yet"
        alert.informativeText = folder.missingFolderMessage
        alert.runModal()
    }

    static func showGrantFailed(_ folder: HeadroomFolder, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Headroom couldn't keep access to the \(folder.title)"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
