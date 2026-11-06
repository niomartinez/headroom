import Foundation
import HeadroomModel
import Testing
@testable import SessionKit

@Suite struct ActivityMappingTests {
    @Test(arguments: [
        ("busy", SessionActivity.working),
        ("BUSY", .working),
        (" busy\n", .working),
        ("waiting", .waitingForInput),
        ("waiting_for_input", .waitingForInput),
        ("needs_permission", .waitingForInput),
        ("Permission", .waitingForInput),
        ("awaiting-input", .waitingForInput),
        ("requires_action", .waitingForInput),
        ("idle", .idle),
        ("done", .idle),
        ("", .idle),
        ("busybody", .idle),
    ])
    func registryStatus(_ status: String, _ expected: SessionActivity) {
        #expect(ActivityMapping.registryStatus(status) == expected)
    }

    @Test func missingRegistryStatusIsIdle() {
        #expect(ActivityMapping.registryStatus(nil) == .idle)
    }

    /// 1.1 §14.1: a `dialog open` wait written in the first minute is a startup dialog, not a question.
    @Test(arguments: [
        ("waiting", "dialog open", 7.7, SessionActivity.idle),
        ("waiting", " Dialog Open ", 59.9, .idle),
        ("waiting", "dialog open", 60, .waitingForInput),
        ("waiting", "dialog open", 61, .waitingForInput),
        ("waiting", "permission prompt", 5, .waitingForInput),
        ("waiting", "input needed", 5, .waitingForInput),
        ("waiting", "something new", 5, .waitingForInput),
        ("waiting", nil, 5, .waitingForInput),
        ("busy", "dialog open", 5, .working),
        ("idle", "dialog open", 5, .idle),
        ("shell", nil, 5, .idle),
    ] as [(String, String?, Double, SessionActivity)])
    func registryStatusWithWaitingFor(_ status: String, _ waitingFor: String?, _ after: Double, _ expected: SessionActivity) {
        let started = Date(timeIntervalSince1970: 1_790_250_000)
        #expect(ActivityMapping.registryStatus(
            status, waitingFor: waitingFor, startedAt: started, statusUpdatedAt: started.addingTimeInterval(after)
        ) == expected)
    }

    /// Without both times the dialog can't be told from a later one, so it keeps 1.0's meaning.
    @Test func dialogOpenWithoutTimesNeedsYou() {
        let started = Date(timeIntervalSince1970: 1_790_250_000)
        #expect(ActivityMapping.registryStatus("waiting", waitingFor: "dialog open", startedAt: nil, statusUpdatedAt: started)
            == .waitingForInput)
        #expect(ActivityMapping.registryStatus("waiting", waitingFor: "dialog open", startedAt: started, statusUpdatedAt: nil)
            == .waitingForInput)
    }

    @Test(arguments: [
        ("UserPromptSubmit", nil, SessionActivity.working),
        ("PreToolUse", nil, .working),
        ("Stop", nil, .idle),
        ("SessionStart", nil, .idle),
        ("Notification", nil, .waitingForInput),
        ("Notification", "", .waitingForInput),
        ("Notification", "permission_prompt", .waitingForInput),
        ("Notification", "elicitation_dialog", .waitingForInput),
        ("Notification", "elicitation_url_dialog", .waitingForInput),
        ("Notification", "agent_needs_input", .waitingForInput),
        ("Notification", "elicitation_complete", .working),
        ("Notification", "elicitation_response", .working),
        ("Notification", "idle_prompt", .idle),
        ("Notification", "auth_success", .idle),
        ("Notification", "agent_completed", .idle),
        ("Notification", "quota_auto_resume_scheduled", .idle),
        ("Notification", "quota_auto_resume_done", .idle),
        ("Notification", "future_type", .idle),
        ("SessionEnd", nil, .idle),
        // Spec §2.5: a tool finished (e.g. after a permission prompt was approved) → working.
        ("PostToolUse", nil, .working),
        ("", nil, .idle),
    ] as [(String, String?, SessionActivity)])
    func hookEvent(_ event: String, _ notificationType: String?, _ expected: SessionActivity) {
        #expect(ActivityMapping.hookEvent(event, notificationType: notificationType) == expected)
    }

    @Test func missingHookEventIsIdle() {
        #expect(ActivityMapping.hookEvent(nil, notificationType: nil) == .idle)
    }

    @Test(arguments: [
        ("2.1.281", [2, 1, 281]),
        ("2.1.281-beta.3", [2, 1, 281]),
        (" 2.10.0 (Claude Code)", [2, 10, 0]),
        ("3", [3]),
        ("2.x", [2]),
    ] as [(String, [Int])])
    func versionComponents(_ version: String, _ expected: [Int]) {
        #expect(ActivityMapping.versionComponents(version) == expected)
    }

    @Test func versionWithoutANumberIsNil() {
        #expect(ActivityMapping.versionComponents("") == nil)
        #expect(ActivityMapping.versionComponents("beta") == nil)
    }

    /// 1.1 §14.1: entries with `waitingFor`, or from 2.1.281 on, report waits themselves.
    @Test(arguments: [
        (nil, nil, false),
        (nil, "2.1.280", false),
        (nil, "2.0.999", false),
        (nil, "2.1", false),
        (nil, "2.1.281", true),
        (nil, "2.1.300", true),
        (nil, "2.2.0", true),
        (nil, "10.0.0", true),
        (nil, "unknown", false),
        ("permission prompt", nil, true),
        ("permission prompt", "2.1.200", true),
    ] as [(String?, String?, Bool)])
    func registryReportsWaits(_ waitingFor: String?, _ version: String?, _ expected: Bool) {
        let entry = RegistryEntry(
            sessionId: "s", pid: 1, cwd: nil, entrypoint: "cli", kind: nil, status: "idle", name: nil,
            startedAt: nil, statusUpdatedAt: nil, waitingFor: waitingFor, version: version
        )
        #expect(ActivityMapping.registryReportsWaits(entry) == expected)
    }

    @Test(arguments: [
        ("claude-desktop", true),
        ("claude-desktop-beta", true),
        ("cli", true),
        ("sdk-cli", false),
        ("sdk-ts", false),
        ("sdk-py", false),
        ("CLI", false),
        ("cli-extra", false),
        ("", false),
    ])
    func entrypointFilter(_ entrypoint: String, _ included: Bool) {
        #expect(ActivityMapping.isSupportedEntrypoint(entrypoint) == included)
    }

    @Test func missingEntrypointIsExcluded() {
        #expect(!ActivityMapping.isSupportedEntrypoint(nil))
    }
}
