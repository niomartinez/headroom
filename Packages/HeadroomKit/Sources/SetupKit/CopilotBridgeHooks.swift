#if HEADROOM_COPILOT_CLI
import Foundation
import HeadroomModel

/// `hooks/headroom.json`: Headroom's own Copilot CLI user hooks file (1.1 §4.9), in Copilot CLI's hooks format
/// version 1. It is a file of its own, so the user's settings and other hook files stay untouched:
///
///     {"version":1,"hooks":{"sessionStart":[{"type":"command","bash":"<command>","timeoutSec":5}], …}}
///
/// Each command does nothing when the bridge script is missing (the hooks file can reach a Mac without it, through
/// dotfiles say, and Copilot CLI would report a failing hook in every session), and otherwise hands the shell over
/// to the bridge, so the bridge's parent is Copilot CLI. Copilot CLI's own payloads don't name their event, so the
/// command does: `bridge.sh hook <event>`.
public enum CopilotBridgeHooks {
    /// The hooks file format Copilot CLI reads.
    public static let formatVersion = 1

    /// Seconds Copilot CLI gives a run before stopping it; the bridge takes well under 100 ms.
    public static let timeoutSeconds = 5

    /// The events Headroom registers, in the order the confirmation dialog names them. `errorOccurred` ends a turn
    /// that failed (an idle session). Never `preToolUse`: a command preToolUse hook that fails denies the tool
    /// call, so a hook there could block the user's tools.
    public static let events = [
        "sessionStart", "userPromptSubmitted", "postToolUse", "notification", "agentStop", "errorOccurred", "sessionEnd",
    ]

    /// How the commands name the bridge script, as one shell word: `"$HOME/.copilot/headroom/bridge.sh"` for the
    /// standard folder (like the terminal bridge's hooks, so the file stays right when a home folder moves), else
    /// the script's absolute path in single quotes (a folder picked for `COPILOT_HOME`).
    public static func scriptReference(paths: CopilotPaths, home: URL = RealHome.url) -> String {
        if paths.copilotDirectory.standardizedFileURL.path == CopilotPaths.standard(home: home).copilotDirectory.standardizedFileURL.path {
            return #""$HOME/.copilot/headroom/bridge.sh""#
        }
        return "'" + paths.bridgeScriptFile.path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// The command registered for `event`.
    public static func command(for event: String, scriptReference: String) -> String {
        "[ ! -f \(scriptReference) ] || exec /bin/bash \(scriptReference) hook \(event)"
    }

    /// The hooks file as a JSON object.
    static func object(scriptReference: String) -> [String: Any] {
        var hooks: [String: Any] = [:]
        for event in events {
            hooks[event] = [
                ["type": "command", "bash": command(for: event, scriptReference: scriptReference), "timeoutSec": timeoutSeconds],
            ]
        }
        return ["version": formatVersion, "hooks": hooks]
    }

    /// The hooks file's contents: sorted keys, indented, with a final newline.
    public static func contents(scriptReference: String) -> Data {
        let data = try? JSONSerialization.data(
            withJSONObject: object(scriptReference: scriptReference),
            options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        )
        // Strings, numbers and nested collections only: the serialization can't fail.
        return (data ?? Data()) + Data("\n".utf8)
    }

    /// Whether `data` is exactly the hooks file for `scriptReference`, as a JSON value (formatting aside).
    static func isCurrent(_ data: Data, scriptReference: String) -> Bool {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return NSDictionary(dictionary: value).isEqual(to: object(scriptReference: scriptReference))
    }
}
#endif
