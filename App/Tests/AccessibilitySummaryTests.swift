import Foundation
import HeadroomModel
import HeadroomUI
import Testing

@Suite struct AccessibilitySummaryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func reading(_ kind: LimitKind, _ percent: Double, resets: Date? = nil, age: TimeInterval = 60) -> LimitReading {
        LimitReading(
            kind: kind, usedPercent: percent, resetsAt: resets, resetIsEstimated: false,
            observedAt: now.addingTimeInterval(-age), source: .desktopApp
        )
    }

    private func session(_ id: String, _ activity: SessionActivity) -> SessionInfo {
        SessionInfo(
            id: id, name: "Session \(id)", projectPath: nil, origin: .desktop, activity: activity,
            activitySince: now, startedAt: now, pid: nil, transcriptPath: nil, context: nil
        )
    }

    private func snapshot(plan: PlanUsage = .empty, sessions: [SessionInfo] = [], issues: Set<DataIssue> = []) -> HeadroomSnapshot {
        HeadroomSnapshot(plan: plan, sessions: sessions, terminalBridgeConnected: false, issues: issues, generatedAt: now)
    }

    @Test func emptySnapshot() {
        let label = AccessibilitySummary.label(for: snapshot(), moment: nil, now: now)
        #expect(label == "Headroom. No plan usage yet. No Claude Code sessions running.")
    }

    @Test func limitsWeeklyFirstThenFiveHour() {
        let plan = PlanUsage(
            fiveHour: reading(.fiveHour, 14, resets: now.addingTimeInterval(3600)),
            weekly: reading(.weekly, 89.4)
        )
        let label = AccessibilitySummary.label(for: snapshot(plan: plan), moment: nil, now: now)
        #expect(label == "Headroom. Weekly limit 89% used. 5-hour limit 14% used. No Claude Code sessions running.")
    }

    @Test func fiveHourWithoutActiveWindowIsNotStarted() {
        let plan = PlanUsage(fiveHour: reading(.fiveHour, 0), weekly: reading(.weekly, 20))
        let label = AccessibilitySummary.label(for: snapshot(plan: plan), moment: nil, now: now)
        #expect(label.contains("5-hour limit not started."))
    }

    @Test func staleReadingsSayHowOldTheyAre() {
        let plan = PlanUsage(weekly: reading(.weekly, 50, age: 42 * 60))
        let label = AccessibilitySummary.label(for: snapshot(plan: plan), moment: nil, now: now)
        #expect(label.contains("Weekly limit 50% used, as of 42 minutes ago."))
    }

    @Test func veryStaleReadingsUseHours() {
        let plan = PlanUsage(weekly: reading(.weekly, 50, age: 3 * 3600 + 120))
        let label = AccessibilitySummary.label(for: snapshot(plan: plan), moment: nil, now: now)
        #expect(label.contains("as of 3 hours ago."))
    }

    /// The panel says "3d ago"; VoiceOver says days too, not "72 hours".
    @Test func readingsADayOldOrMoreUseDays() {
        let threeDays = PlanUsage(weekly: reading(.weekly, 50, age: 72 * 3600 + 60))
        #expect(AccessibilitySummary.label(for: snapshot(plan: threeDays), moment: nil, now: now).contains("as of 3 days ago."))
        let oneDay = PlanUsage(weekly: reading(.weekly, 50, age: 25 * 3600))
        #expect(AccessibilitySummary.label(for: snapshot(plan: oneDay), moment: nil, now: now).contains("as of 1 day ago."))
        let almostADay = PlanUsage(weekly: reading(.weekly, 50, age: 23 * 3600 + 59 * 60))
        #expect(AccessibilitySummary.label(for: snapshot(plan: almostADay), moment: nil, now: now).contains("as of 23 hours ago."))
    }

    // MARK: Data issues (spec §4: never read "can't see" as "nothing there")

    /// First launch of the store build, before any grant.
    @Test func missingFolderAccessIsNotNoSessions() {
        let label = AccessibilitySummary.label(
            for: snapshot(issues: [.claudeCodeFolderUnavailable, .desktopFolderUnavailable]), moment: nil, now: now
        )
        #expect(label == "Headroom. Needs access to your Claude folders.")
    }

    @Test func missingClaudeCodeFolderAccessIsNotNoSessions() {
        let label = AccessibilitySummary.label(for: snapshot(issues: [.claudeCodeFolderUnavailable]), moment: nil, now: now)
        #expect(label == "Headroom. Needs access to ~/.claude to see sessions. No plan usage yet.")
        #expect(!label.contains("No Claude Code sessions running"))
    }

    @Test func missingDesktopFolderAccessIsNotNoPlanUsage() {
        let sessions = [session("1", .working)]
        let label = AccessibilitySummary.label(for: snapshot(sessions: sessions, issues: [.desktopFolderUnavailable]), moment: nil, now: now)
        #expect(label == "Headroom. Needs access to the Claude app's folder to read limits. Sessions: 1 working.")
    }

    @Test func missingDesktopFolderAccessKeepsTerminalLimits() {
        let plan = PlanUsage(weekly: reading(.weekly, 40))
        let label = AccessibilitySummary.label(for: snapshot(plan: plan, issues: [.desktopFolderUnavailable]), moment: nil, now: now)
        #expect(label == "Headroom. Needs access to the Claude app's folder to read limits. Weekly limit 40% used. No Claude Code sessions running.")
    }

    @Test func unreadableSessionRegistryIsNotNoSessions() {
        let label = AccessibilitySummary.label(for: snapshot(issues: [.sessionRegistryUnreadable]), moment: nil, now: now)
        #expect(label == "Headroom. No plan usage yet. Can't read Claude Code sessions.")
    }

    /// Sessions the bridge still reports are listed even when the registry can't be read.
    @Test func unreadableRegistryWithSessionsStillCountsThem() {
        let sessions = [session("1", .idle)]
        let label = AccessibilitySummary.label(for: snapshot(sessions: sessions, issues: [.sessionRegistryUnreadable]), moment: nil, now: now)
        #expect(label.hasSuffix("Sessions: 1 idle."))
    }

    @Test func unrecognizedUsageDataIsNotNoPlanUsage() {
        let label = AccessibilitySummary.label(for: snapshot(issues: [.desktopUsageUnrecognized]), moment: nil, now: now)
        #expect(label == "Headroom. Usage data not recognized. No Claude Code sessions running.")
    }

    @Test func aMomentStillLeadsWhenAccessIsMissing() {
        let moment = Moment.limitCrossed(kind: .weekly, percent: 90)
        let label = AccessibilitySummary.label(for: snapshot(issues: [.claudeCodeFolderUnavailable]), moment: moment, now: now)
        #expect(label.hasPrefix("Headroom. Weekly limit at 90%. Needs access to ~/.claude to see sessions."))
    }

    @Test func percentagesAreClampedForSpeech() {
        let plan = PlanUsage(weekly: reading(.weekly, 104))
        let label = AccessibilitySummary.label(for: snapshot(plan: plan), moment: nil, now: now)
        #expect(label.contains("Weekly limit 100% used."))
    }

    @Test func sessionsAreCountedByActivityOmittingEmptyGroups() {
        let sessions = [session("1", .working), session("2", .waitingForInput), session("3", .waitingForInput)]
        let label = AccessibilitySummary.label(for: snapshot(sessions: sessions), moment: nil, now: now)
        #expect(label.hasSuffix("Sessions: 1 working, 2 need input."))
    }

    @Test func singleWaitingAndIdleSessions() {
        let sessions = [session("1", .waitingForInput), session("2", .idle)]
        let label = AccessibilitySummary.label(for: snapshot(sessions: sessions), moment: nil, now: now)
        #expect(label.hasSuffix("Sessions: 1 needs input, 1 idle."))
    }

    @Test func showingMomentLeadsTheLabel() {
        let moment = Moment.sessionNeedsInput(sessionID: "x", name: "Refactor parser")
        let label = AccessibilitySummary.label(for: snapshot(), moment: moment, now: now)
        #expect(label.hasPrefix("Headroom. Refactor parser needs your input."))
    }

    /// 1.1 §14.4: while the pill rests on "(!) Refactor parser", VoiceOver says who needs you first.
    @Test func theRestStateLeadsTheLabel() {
        let sessions = [session("1", .waitingForInput)]
        let label = AccessibilitySummary.label(
            for: snapshot(sessions: sessions), moment: nil, now: now, attention: NeedsYouAttention(names: ["Refactor parser"])
        )
        #expect(label == "Headroom. Refactor parser needs your input. No plan usage yet. Sessions: 1 needs input.")
    }

    /// A moment says it already; the rest state follows once it ends.
    @Test func aMomentWinsOverTheRestState() {
        let moment = Moment.sessionFinished(sessionID: "x", name: "Write docs")
        let label = AccessibilitySummary.label(
            for: snapshot(), moment: moment, now: now, attention: NeedsYouAttention(names: ["Refactor parser", "Atlas"])
        )
        #expect(label.hasPrefix("Headroom. Write docs finished. No plan usage yet."))
        #expect(!label.contains("need your input"))
    }

    /// Dismissed waits are counted apart, whether the snapshot still says waiting or already reads them as idle.
    @Test func dismissedWaitsAreCountedApart() {
        let raw = [session("1", .waitingForInput), session("2", .waitingForInput), session("3", .idle)]
        let presented = [session("1", .waitingForInput), session("2", .idle), session("3", .idle)]
        for sessions in [raw, presented] {
            let label = AccessibilitySummary.label(for: snapshot(sessions: sessions), moment: nil, now: now, dismissedIDs: ["2"])
            #expect(label.hasSuffix("Sessions: 1 needs input, 1 dismissed, 1 idle."))
        }
    }

    /// A dismissed session that went back to work counts as working.
    @Test func aDismissedSessionAtWorkIsWorking() {
        let sessions = [session("1", .working)]
        let label = AccessibilitySummary.label(for: snapshot(sessions: sessions), moment: nil, now: now, dismissedIDs: ["1"])
        #expect(label.hasSuffix("Sessions: 1 working."))
    }

    @Test func momentTexts() {
        #expect(AccessibilitySummary.text(for: .sessionFinished(sessionID: "a", name: "Write docs")) == "Write docs finished")
        #expect(AccessibilitySummary.text(for: .sessionNeedsInput(sessionID: "a", name: "Write docs")) == "Write docs needs your input")
        #expect(AccessibilitySummary.text(for: .limitCrossed(kind: .weekly, percent: 90)) == "Weekly limit at 90%")
        #expect(AccessibilitySummary.text(for: .limitCrossed(kind: .fiveHour, percent: 100)) == "5-hour limit reached")
    }
}
