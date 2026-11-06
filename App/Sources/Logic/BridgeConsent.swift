import SetupKit

/// The confirmation shown before Connect terminal edits the user's Claude Code settings (spec §2.6).
enum BridgeConsent {
    static let title = "Connect terminal sessions?"

    /// Names the hooks from `BridgeInstaller.hookEvents`, so the dialog always lists exactly what
    /// the installer adds.
    static let message = """
        Headroom will change ~/.claude/settings.json:

        • statusLine: runs ~/.claude/headroom/bridge.sh. If you already have a status line, \
        Headroom keeps it and still shows its output.
        • hooks: adds one entry each for \(list(BridgeInstaller.hookEvents)) that runs the same \
        script. Your other hooks and settings stay as they are.

        The script saves limits, context size and session status to ~/.claude/headroom, and never \
        your prompts. The first time Headroom changes settings.json, it copies the file to \
        ~/.claude/settings.json.headroom-backup and never overwrites that backup. Disconnect \
        removes everything Headroom added.

        Choose Disconnect before you delete Headroom: Claude Code keeps running the script until \
        these entries are removed.

        New terminal sessions pick this up; sessions that are already running don't.
        """

    static let confirmButton = "Connect"

    /// "A, B and C".
    static func list(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        let rest = items.dropLast()
        return rest.isEmpty ? last : rest.joined(separator: ", ") + " and " + last
    }
}

/// Shown after Disconnect terminal succeeds (spec §2.6).
enum BridgeDisconnectNotice {
    static let title = "Terminal disconnected"

    /// Claude Code reads its hooks when a session starts, so sessions already running keep calling
    /// the deleted bridge script until they're restarted: in a terminal, and in the Claude desktop
    /// app, whose Claude Code sessions read the same settings.json.
    static let message = "Claude Code sessions that are already running, in a terminal or in the Claude app, still point at the removed bridge until you restart them, which is harmless because they skip it once it's gone."
}
