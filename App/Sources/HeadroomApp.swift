import AppKit

/// Menu bar only (`LSUIElement`): no Dock icon and no windows at launch, except Settings as
/// onboarding on the first run (spec §1.3). `--render-live <dir>` renders the live pill and panel
/// to PNG instead and quits (see `LiveRenderer`).
@main
enum HeadroomApp {
    @MainActor
    static func main() {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let mode: LaunchMode
        switch LaunchOptions.mode(from: CommandLine.arguments, currentDirectory: currentDirectory) {
        case let .success(parsed):
            mode = parsed
        case .failure:
            FileHandle.standardError.write(Data((LaunchOptions.usage + "\n").utf8))
            exit(64) // EX_USAGE
        }

        let app = NSApplication.shared
        let delegate = AppDelegate(mode: mode)
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let mode: LaunchMode
    private var coordinator: AppCoordinator?
    private var liveRenderer: LiveRenderer?
    /// URLs that arrived before the coordinator was running.
    private var pendingURLs: [URL] = []

    init(mode: LaunchMode) {
        self.mode = mode
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch mode {
        case .menuBar:
            NSApplication.shared.mainMenu = MainMenu.make()
            let coordinator = AppCoordinator()
            self.coordinator = coordinator
            coordinator.start()
            let urls = pendingURLs
            pendingURLs = []
            if !urls.isEmpty {
                // After the status item has been laid out, so the panel can hang from it.
                Task { @MainActor in urls.forEach(coordinator.open) }
            }
        case let .renderLive(directory):
            let renderer = LiveRenderer(directory: directory)
            liveRenderer = renderer
            renderer.start()
        }
    }

    /// Opening Headroom again while it runs (Finder, Spotlight, Launchpad) shows Settings. It is the
    /// only way back to Settings and Quit when the pill isn't visible: hidden behind the notch,
    /// turned off in System Settings › Menu Bar, or tucked away by a menu bar manager.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.showSettings()
        return false
    }

    /// `com.niomartinez.headroom://panel`: a widget was clicked (1.1 §5.6). `--render-live` ignores URLs.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard mode == .menuBar else { return }
        guard let coordinator else {
            pendingURLs += urls
            return
        }
        urls.forEach(coordinator.open)
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
        liveRenderer?.stop()
    }
}
