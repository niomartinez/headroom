import Foundation
import HeadroomModel

/// How raw registry and hook values are interpreted: which entrypoints count, and which
/// `SessionActivity` a status or hook event means (spec §2.2, §2.5, 1.1 §14.1).
public enum ActivityMapping {
    static let cliEntrypoint = "cli"
    static let notificationEvent = "Notification"
    static let sessionEndEvent = "SessionEnd"

    /// Spec §2.2: only the desktop app (`claude-desktop…`) and `cli`; SDK sessions started by
    /// plugins (`sdk-cli`, `sdk-ts`, …) and entries without an entrypoint are left out.
    public static func isSupportedEntrypoint(_ entrypoint: String?) -> Bool {
        guard let entrypoint else { return false }
        return entrypoint == cliEntrypoint || entrypoint.hasPrefix("claude-desktop")
    }

    /// `waitingFor` of a dialog Claude Code opens by itself (a startup nudge), not a question about the work.
    static let dialogOpen = "dialog open"
    /// A `dialog open` wait written this soon after the session started is a startup dialog (1.1 §14.1): Claude
    /// Code writes it 7–8 s after launch, and the session may sit on it for hours without needing anything.
    public static let startupDialogWindow: TimeInterval = 60

    /// Spec §2.2, 1.1 §14.1: `busy` → working; anything mentioning wait/permission/input/action →
    /// waitingForInput, except a startup dialog (`waitingFor` "dialog open" written less than
    /// `startupDialogWindow` after `startedAt`) → idle; everything else, including a missing status → idle.
    /// Other `waitingFor` values (CLI ≥ 2.1.281 writes "permission prompt", "input needed", "sandbox request",
    /// "goal proposal", …) and a missing one keep 1.0's waitingForInput.
    public static func registryStatus(
        _ status: String?,
        waitingFor: String? = nil,
        startedAt: Date? = nil,
        statusUpdatedAt: Date? = nil
    ) -> SessionActivity {
        let status = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if status == "busy" { return .working }
        guard ["wait", "permission", "input", "action"].contains(where: status.contains) else { return .idle }
        return isStartupDialog(waitingFor, startedAt: startedAt, statusUpdatedAt: statusUpdatedAt) ? .idle : .waitingForInput
    }

    static func isStartupDialog(_ waitingFor: String?, startedAt: Date?, statusUpdatedAt: Date?) -> Bool {
        guard waitingFor?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == dialogOpen,
              let startedAt, let statusUpdatedAt
        else { return false }
        return statusUpdatedAt.timeIntervalSince(startedAt) < startupDialogWindow
    }

    /// Notification types that mean the session is blocked on the user (1.1 §14.1). Copilot CLI's bridge uses the
    /// same names (`CopilotSessionRecord`).
    public static let needsYouNotificationTypes: Set<String> = [
        "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input",
    ]
    /// Notification types that mean the question was answered and the agent carries on.
    public static let resumedNotificationTypes: Set<String> = ["elicitation_complete", "elicitation_response"]

    /// Spec §2.5, 1.1 §14.1: `UserPromptSubmit`/`PreToolUse`/`PostToolUse` → working (`PostToolUse` also
    /// ends "needs you" once a permission prompt is approved). `Notification` → waitingForInput for the
    /// needs-you types and for a missing or empty type (CLIs from before `notification_type`); working for
    /// `elicitation_complete`/`elicitation_response`; idle for `idle_prompt`, `auth_success`, `agent_completed`,
    /// `quota_auto_resume_*` and any type not known yet. `Stop`, `SessionStart` and anything unknown → idle.
    public static func hookEvent(_ event: String?, notificationType: String?) -> SessionActivity {
        switch event {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse":
            .working
        case notificationEvent:
            notificationActivity(notificationType)
        default:
            .idle
        }
    }

    static func notificationActivity(_ type: String?) -> SessionActivity {
        guard let type, !type.isEmpty else { return .waitingForInput }
        if needsYouNotificationTypes.contains(type) { return .waitingForInput }
        return resumedNotificationTypes.contains(type) ? .working : .idle
    }

    /// The Claude Code version from which the registry reports waits itself (`status` "waiting" with `waitingFor`).
    static let waitReportingVersion = [2, 1, 281]

    /// True when the registry entry says by itself when the session waits (1.1 §14.1): it has `waitingFor`, or it
    /// was written by Claude Code 2.1.281 or later. Its status then already covers a notification of the same
    /// second.
    static func registryReportsWaits(_ entry: RegistryEntry) -> Bool {
        if entry.waitingFor != nil { return true }
        guard let version = entry.version.flatMap(versionComponents) else { return false }
        return !version.lexicographicallyPrecedes(waitReportingVersion)
    }

    /// `"2.1.281"` → `[2, 1, 281]`; the leading dot-separated numbers of a version string, so a suffix such as
    /// `-beta.1` or ` (Claude Code)` is ignored. Nil without a leading number.
    static func versionComponents(_ version: String) -> [Int]? {
        var components: [Int] = []
        for part in version.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false) {
            let digits = part.prefix { $0.isASCII && $0.isNumber }
            guard !digits.isEmpty, let number = Int(digits) else { break }
            components.append(number)
            if digits.count < part.count { break }
        }
        return components.isEmpty ? nil : components
    }
}
