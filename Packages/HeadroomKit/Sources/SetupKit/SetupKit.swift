import Foundation

// SetupKit: the terminal bridge (spec §2.4, §2.5) and its installer (spec §2.6).
// `BridgeScript` lives in BridgeScript.swift, `BridgeInstaller` in BridgeInstaller.swift.

public enum BridgeInstallState: Sendable, Equatable {
    case notInstalled
    case installed
    /// Present but an older script version or partially removed entries.
    case outdated
    /// settings.json exists but can't be read or parsed; the message says why (for instance that it
    /// links outside the folders Headroom can access, `BridgeInstallError.settingsOutsideGrant`).
    case settingsUnreadable(String)
}

public enum BridgeInstallError: Error, Equatable {
    case settingsUnreadable(String)
    case writeFailed(String)
    /// settings.json is a symbolic link to `target`, outside ~/.claude, which Headroom may not open
    /// (the sandboxed app can open only the folder the user granted). Nothing was changed; the file
    /// itself is fine, so it must not be "fixed" or removed. `state()` reports this as
    /// `.settingsUnreadable` with a message naming the target.
    case settingsOutsideGrant(target: String)

    /// The reason for `state()`'s `.settingsUnreadable`.
    var unreadableReason: String? {
        switch self {
        case .settingsUnreadable(let reason): reason
        case .settingsOutsideGrant(let target): "settings.json links to \(target), outside the folders Headroom can access"
        case .writeFailed: nil
        }
    }
}

extension BridgeInstallError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .settingsUnreadable(let reason), .writeFailed(let reason):
            reason
        case .settingsOutsideGrant(let target):
            "~/.claude/settings.json links to \(target), outside the folders Headroom can access, "
                + "so Headroom can't read or change it. Nothing was changed."
        }
    }
}
