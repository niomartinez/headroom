import Foundation

/// Headroom's entries in a settings object: recognizing them, adding them, removing them.
///
/// An entry is ours when its command mentions the bridge path, so entries written by older
/// versions (with a different command line) are still found, repaired and removed.
enum BridgeEntries {
    static let marker = ".claude/headroom/bridge.sh"

    /// Our status line entry, keeping the other keys of `options` (the entry it replaces, or the saved
    /// original): Claude Code reads `refreshInterval`, `padding` and `hideVimModeIndicator` there, and a
    /// chained status line must keep refreshing and laying out the way the user set it up.
    static func statusLine(keepingOptionsOf options: Any?...) -> [String: Any] {
        var entry: [String: Any] = [:]
        for case let object as [String: Any] in options {
            entry.merge(object) { _, new in new }
        }
        entry["type"] = "command"
        entry["command"] = BridgeInstaller.statusLineCommand
        return entry
    }

    static func hookGroup(for event: String) -> [String: Any] {
        let hook: [String: Any] = ["type": "command", "command": BridgeInstaller.hookCommand, "timeout": 5]
        return BridgeInstaller.matcherEvents.contains(event) ? ["matcher": "", "hooks": [hook]] : ["hooks": [hook]]
    }

    static func isOurStatusLine(_ value: Any?) -> Bool {
        isOurs((value as? [String: Any])?["command"])
    }

    /// Other keys (the user's options) don't matter.
    static func isCurrentStatusLine(_ value: Any?) -> Bool {
        guard let entry = value as? [String: Any] else { return false }
        return entry["type"] as? String == "command" && entry["command"] as? String == BridgeInstaller.statusLineCommand
    }

    /// True when a settings object holds our status line or any hook of ours.
    static func hasAny(in settings: [String: Any]) -> Bool {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        return isOurStatusLine(settings["statusLine"])
            || hooks.values.contains { ourHookCount(in: $0 as? [Any] ?? []) > 0 }
    }

    /// How many of our hook commands an event's groups hold.
    static func ourHookCount(in groups: [Any]) -> Int {
        groups.reduce(0) { count, group in
            count + hooks(of: group).filter { isOurs(($0 as? [String: Any])?["command"]) }.count
        }
    }

    /// True when an event holds exactly our current group and no other hook of ours.
    static func isCurrent(_ groups: [Any]?, event: String) -> Bool {
        guard let groups else { return false }
        let expected = hookGroup(for: event)
        return ourHookCount(in: groups) == 1 && groups.contains { jsonValuesEqual($0, expected) }
    }

    /// The groups with our hooks taken out. A group left without hooks because of that is
    /// dropped; everything else stays exactly as it was.
    static func removingOurHooks(from groups: [Any]) -> [Any] {
        groups.compactMap { group -> Any? in
            guard var object = group as? [String: Any], let hooks = object["hooks"] as? [Any] else { return group }
            let kept = hooks.filter { !isOurs(($0 as? [String: Any])?["command"]) }
            if kept.count == hooks.count { return group }
            if kept.isEmpty { return nil }
            object["hooks"] = kept
            return object
        }
    }

    private static func hooks(of group: Any) -> [Any] {
        (group as? [String: Any])?["hooks"] as? [Any] ?? []
    }

    private static func isOurs(_ command: Any?) -> Bool {
        (command as? String)?.contains(marker) == true
    }
}

/// Value equality of two JSON values (as JSONSerialization parses or writes them).
func jsonValuesEqual(_ a: Any?, _ b: Any?) -> Bool {
    switch (a, b) {
    case (nil, nil): true
    case let (a?, b?): (a as AnyObject).isEqual(b as AnyObject)
    default: false
    }
}
