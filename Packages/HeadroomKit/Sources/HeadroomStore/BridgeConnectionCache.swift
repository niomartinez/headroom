import Foundation
import SetupKit

/// The terminal bridge's install state (spec §2.6), checked again only when `settings.json` or `bridge.sh`
/// change stamp (or appear or disappear): the check parses the whole settings file.
struct BridgeConnectionCache {
    let installer: BridgeInstaller
    private var stamps: [FileStamp?]?
    private var cached: BridgeInstallState?
    /// Number of times the state was computed (for tests).
    private(set) var checks = 0

    init(claudeDirectory: URL) {
        installer = BridgeInstaller(claudeDirectory: claudeDirectory)
    }

    mutating func state() -> BridgeInstallState {
        let current = [FileStamp.of(installer.settingsFile), FileStamp.of(installer.scriptFile)]
        if let cached, current == stamps {
            return cached
        }
        let fresh = installer.state()
        checks += 1
        stamps = current
        cached = fresh
        return fresh
    }

    /// `terminalBridgeConnected`: installed, or installed with an older script (still reporting).
    static func isConnected(_ state: BridgeInstallState) -> Bool {
        state == .installed || state == .outdated
    }
}
