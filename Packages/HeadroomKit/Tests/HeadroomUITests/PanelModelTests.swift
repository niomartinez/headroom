import Foundation
import HeadroomModel
import Testing
@testable import HeadroomUI

@Suite struct PanelModelTests {
    let now = Fixture.now
    let sunday7pm = Fixture.date(2026, 9, 27, 19, 0)

    private func model(_ snapshot: HeadroomSnapshot, idleExpanded: Bool = false) -> PanelModel {
        PanelModel(snapshot: snapshot, now: now, idleExpanded: idleExpanded, format: Fixture.format)
    }

    private func idle(_ count: Int) -> [SessionInfo] {
        (1...count).map { Fixture.session("i\($0)", .idle) }
    }

    // MARK: Grouping

    @Test func groupsIntoWorkingNeedsYouIdle() {
        let sessions = [Fixture.session("w1", .working), Fixture.session("q1", .waitingForInput)] + idle(2)
        let panel = model(Fixture.snapshot(sessions: sessions))
        #expect(panel.sections.map(\.kind) == [.working, .needsYou, .idle])
        #expect(panel.sections.map(\.title) == ["Working", "Needs you", "Idle"])
        #expect(panel.sections.map { $0.rows.map(\.id) } == [["w1"], ["q1"], ["i1", "i2"]])
    }

    @Test func emptyGroupsAreOmitted() {
        let panel = model(Fixture.snapshot(sessions: idle(2)))
        #expect(panel.sections.map(\.kind) == [.idle])
    }

    @Test func orderInsideAGroupIsPreserved() {
        let sessions = [
            Fixture.session("i2", .idle), Fixture.session("w2", .working),
            Fixture.session("i1", .idle), Fixture.session("w1", .working),
        ]
        let panel = model(Fixture.snapshot(sessions: sessions))
        #expect(panel.sections.map { $0.rows.map(\.id) } == [["w2", "w1"], ["i2", "i1"]])
    }

    // MARK: Idle collapse

    @Test func idleCollapsesToThreeWithShowMore() {
        let idleSection = model(Fixture.snapshot(sessions: idle(7))).sections.last
        #expect(idleSection?.rows.map(\.id) == ["i1", "i2", "i3"])
        #expect(idleSection?.hiddenCount == 4)
        #expect(idleSection?.toggleTitle == "Show 4 more")
    }

    @Test func expandedIdleShowsAllWithShowLess() {
        let idleSection = model(Fixture.snapshot(sessions: idle(7)), idleExpanded: true).sections.last
        #expect(idleSection?.rows.count == 7)
        #expect(idleSection?.hiddenCount == 0)
        #expect(idleSection?.toggleTitle == "Show less")
    }

    @Test func threeIdleNeedNoToggle() {
        let idleSection = model(Fixture.snapshot(sessions: idle(3))).sections.last
        #expect(idleSection?.rows.count == 3)
        #expect(idleSection?.toggleTitle == nil)
        #expect(model(Fixture.snapshot(sessions: idle(4))).sections.last?.toggleTitle == "Show 1 more")
    }

    @Test func activeGroupsNeverCollapse() {
        let working = (1...6).map { Fixture.session("w\($0)", .working) }
        let section = model(Fixture.snapshot(sessions: working)).sections.first
        #expect(section?.rows.count == 6)
        #expect(section?.toggleTitle == nil)
    }

    // MARK: Header

    @Test func weeklyRowExactReset() {
        let plan = PlanUsage(weekly: Fixture.reading(.weekly, 89, resetsAt: sunday7pm))
        let row = model(Fixture.snapshot(plan: plan)).weekly
        #expect(row.title == "Weekly")
        #expect(row.badge == PercentBadge(text: "89%", severity: .warning))
        #expect(row.detail == "resets Sun 7 PM")
    }

    @Test func weeklyRowEstimatedAndStale() {
        let plan = PlanUsage(weekly: Fixture.reading(.weekly, 89, resetsAt: sunday7pm, estimated: true, age: 42 * 60))
        #expect(model(Fixture.snapshot(plan: plan)).weekly.detail == "resets ~Sun 7 PM · as of 42m ago")
    }

    @Test func weeklyRowUnknownReset() {
        let plan = PlanUsage(weekly: Fixture.reading(.weekly, 30, resetsAt: nil, estimated: true))
        #expect(model(Fixture.snapshot(plan: plan)).weekly.detail == "reset unknown")
        // The weekly limit resets on a schedule, so an unused week is not "not started" either.
        let unused = PlanUsage(weekly: Fixture.reading(.weekly, 0, resetsAt: nil, estimated: true))
        #expect(model(Fixture.snapshot(plan: unused)).weekly.detail == "reset unknown")
    }

    @Test func fiveHourRow() {
        let reset = now.addingTimeInterval(2 * 3600 + 50 * 60)
        let exact = model(Fixture.snapshot(plan: PlanUsage(fiveHour: Fixture.reading(.fiveHour, 14, resetsAt: reset)))).fiveHour
        #expect(exact.title == "5-hour")
        #expect(exact.badge == PercentBadge(text: "14%", severity: .normal))
        #expect(exact.detail == "resets in 2h 50m")
        let estimated = PlanUsage(fiveHour: Fixture.reading(.fiveHour, 14, resetsAt: reset, estimated: true))
        #expect(model(Fixture.snapshot(plan: estimated)).fiveHour.detail == "resets ~in 2h 50m")
        let idleWindow = PlanUsage(fiveHour: Fixture.reading(.fiveHour, 0, resetsAt: nil))
        #expect(model(Fixture.snapshot(plan: idleWindow)).fiveHour.detail == "not started")
    }

    @Test func fiveHourUsageWithoutAResetTimeIsNotNotStarted() {
        // UsageKit returns a 5-hour reading with usage but no reset when the inferred window end is
        // already past (spec §3.2). "14%" next to "not started" contradicts itself.
        let used = PlanUsage(fiveHour: Fixture.reading(.fiveHour, 14, resetsAt: nil, estimated: true))
        let row = model(Fixture.snapshot(plan: used)).fiveHour
        #expect(row.badge == PercentBadge(text: "14%", severity: .normal))
        #expect(row.detail == "reset unknown")
        let stale = PlanUsage(fiveHour: Fixture.reading(.fiveHour, 14, resetsAt: nil, estimated: true, age: 42 * 60))
        #expect(model(Fixture.snapshot(plan: stale)).fiveHour.detail == "reset unknown · as of 42m ago")
        // A window that is not open (0 %, spec §3.1) still reads "not started", also when it rounds to 0.
        let barely = PlanUsage(fiveHour: Fixture.reading(.fiveHour, 0.3, resetsAt: nil))
        #expect(model(Fixture.snapshot(plan: barely)).fiveHour.detail == "not started")
    }

    @Test func fiveHourUsageWhoseResetJustPassedIsNotNotStarted() {
        // Between polls a reset can pass before the next snapshot rolls the reading over (§3.1):
        // "not started" is only for a reading without usage.
        let passed = now.addingTimeInterval(-30)
        let used = PlanUsage(fiveHour: Fixture.reading(.fiveHour, 14, resetsAt: passed))
        #expect(model(Fixture.snapshot(plan: used)).fiveHour.detail == "reset unknown")
        let unused = PlanUsage(fiveHour: Fixture.reading(.fiveHour, 0, resetsAt: passed))
        #expect(model(Fixture.snapshot(plan: unused)).fiveHour.detail == "not started")
        // An open window at 0 % still counts down.
        let open = PlanUsage(fiveHour: Fixture.reading(.fiveHour, 0, resetsAt: now.addingTimeInterval(3600)))
        #expect(model(Fixture.snapshot(plan: open)).fiveHour.detail == "resets in 1h")
    }

    @Test func missingReadingHidesTheNumber() {
        let row = model(Fixture.snapshot(plan: .empty)).weekly
        #expect(row.badge == nil)
        #expect(row.detail == "no data yet")
        let unrecognized = model(Fixture.snapshot(plan: .empty, issues: [.desktopUsageUnrecognized]))
        #expect(unrecognized.fiveHour.detail == "usage data not recognized")
    }

    @Test func extraUsageOnlyWhenPositive() {
        #expect(model(Fixture.snapshot(plan: Fixture.plan(weekly: 50, fiveHour: 5, extra: 12))).extraUsage == "Extra usage 12%")
        #expect(model(Fixture.snapshot(plan: Fixture.plan(weekly: 50, fiveHour: 5, extra: 0))).extraUsage == nil)
        #expect(model(Fixture.snapshot(plan: Fixture.plan(weekly: 50, fiveHour: 5, extra: nil))).extraUsage == nil)
        #expect(model(Fixture.snapshot(plan: Fixture.plan(weekly: 50, fiveHour: 5, extra: .nan))).extraUsage == nil)
    }

    @Test func gaugeMatchesThePlan() {
        let panel = model(Fixture.snapshot(plan: Fixture.plan(weekly: 89, fiveHour: 14, age: 42 * 60)))
        #expect(panel.gauge.outer?.fraction == 0.89)
        #expect(panel.gauge.isStale)
    }

    // MARK: Rows

    @Test func rowShowsNameProjectAndContext() {
        let session = Fixture.session(
            "w1", .working, name: "Tidy build script", path: "/Users/me/code/atlas",
            context: Fixture.context(724_000, of: 1_000_000, model: "claude-opus-5-5")
        )
        let row = model(Fixture.snapshot(sessions: [session])).sections.first?.rows.first
        #expect(row?.name == "Tidy build script")
        #expect(row?.projectName == "atlas")
        #expect(row?.isTerminal == false)
        #expect(row?.dot == .working)
        #expect(row?.context == ContextBadge(fraction: 0.724, text: "72%", severity: .normal))
        #expect(row?.helpText == "724k of 1M tokens · claude-opus-5-5")
    }

    @Test func contextUsesContextThresholds() {
        func severity(_ used: Int) -> Severity? {
            let session = Fixture.session("a", .idle, context: Fixture.context(used, of: 200_000))
            return model(Fixture.snapshot(sessions: [session])).sections.first?.rows.first?.context?.severity
        }
        #expect(severity(148_000) == .normal)
        #expect(severity(150_000) == .warning)
        #expect(severity(180_000) == .critical)
    }

    @Test func terminalRowWithoutContextOrModel() {
        let terminal = Fixture.session("t1", .waitingForInput, name: "harbor", path: "/Users/me/code/harbor", origin: .terminal)
        let row = model(Fixture.snapshot(sessions: [terminal])).sections.first?.rows.first
        #expect(row?.isTerminal == true)
        #expect(row?.dot == .waiting)
        #expect(row?.projectName == nil)
        #expect(row?.context == nil)
        #expect(row?.helpText == nil)

        let noModel = Fixture.session("a", .idle, context: Fixture.context(52_400, of: 200_000, model: nil))
        #expect(model(Fixture.snapshot(sessions: [noModel])).sections.first?.rows.first?.helpText == "52k of 200k tokens")
    }

    /// A window size that is only a guess gets no percent: the token count, an empty bar and no
    /// warning color, however close to the guessed 200k it is.
    @Test(arguments: [(168_236, "168k"), (199_600, "200k"), (850, "850"), (0, "0")])
    func assumedWindowShowsTheTokenCountOnly(used: Int, text: String) {
        let session = Fixture.session(
            "a", .working, context: Fixture.context(used, of: 200_000, model: "claude-opus-4-5", assumed: true)
        )
        let row = model(Fixture.snapshot(sessions: [session])).sections.first?.rows.first
        #expect(row?.context == ContextBadge(fraction: 0, text: text, severity: .normal, windowIsAssumed: true))
        #expect(row?.helpText == "\(text) tokens · claude-opus-4-5")
        #expect(row?.accessibilityValue == "context \(text) tokens")
    }

    @Test func assumedWindowWithoutModelShowsTheTokenCount() {
        let session = Fixture.session("a", .idle, context: Fixture.context(52_400, of: 200_000, model: nil, assumed: true))
        let row = model(Fixture.snapshot(sessions: [session])).sections.first?.rows.first
        #expect(row?.context?.text == "52k")
        #expect(row?.helpText == "52k tokens")
    }

    @Test func knownWindowStillShowsAPercent() {
        let session = Fixture.session("a", .idle, context: Fixture.context(168_236, of: 200_000, model: "claude-haiku-4-5"))
        let row = model(Fixture.snapshot(sessions: [session])).sections.first?.rows.first
        #expect(row?.context == ContextBadge(fraction: 0.84118, text: "84%", severity: .warning))
        #expect(row?.context?.windowIsAssumed == false)
        #expect(row?.helpText == "168k of 200k tokens · claude-haiku-4-5")
    }

    // MARK: VoiceOver

    @Test func rowSpeaksNameFolderStateAndContext() {
        let working = Fixture.session(
            "w1", .working, name: "Refactor invoice export", path: "/Users/me/code/ledger",
            context: Fixture.context(720_000, of: 1_000_000)
        )
        let terminal = Fixture.session(
            "t1", .waitingForInput, name: "Rename keys", path: "/Users/me/code/harbor", origin: .terminal,
            context: Fixture.context(130_000, of: 200_000)
        )
        let idle = Fixture.session("i1", .idle, name: "atlas", path: "/Users/me/code/atlas")
        let rows = model(Fixture.snapshot(sessions: [working, terminal, idle])).sections.flatMap(\.rows)

        #expect(rows.map(\.accessibilityLabel) == [
            "Refactor invoice export, ledger, working",
            "Rename keys, harbor, terminal, needs input",
            "atlas, idle",
        ])
        // The percent says what it measures.
        #expect(rows.map(\.accessibilityValue) == ["context 72% full", "context 65% full", nil])
    }

    @Test func limitRowSpeaksWhatTheMarkersMean() {
        let exact = PlanUsage(
            fiveHour: Fixture.reading(.fiveHour, 14, resetsAt: now.addingTimeInterval(2 * 3600 + 50 * 60)),
            weekly: Fixture.reading(.weekly, 89, resetsAt: sunday7pm)
        )
        let panel = model(Fixture.snapshot(plan: exact))
        #expect(panel.weekly.accessibilityLabel == "Weekly limit")
        #expect(panel.weekly.accessibilityValue == "89% used, resets Sunday 7 PM")
        #expect(panel.fiveHour.accessibilityLabel == "5-hour limit")
        #expect(panel.fiveHour.accessibilityValue == "14% used, resets in 2 hours 50 minutes")

        // "~" is an estimate: say so instead of reading a tilde (or nothing).
        let estimated = PlanUsage(
            fiveHour: Fixture.reading(.fiveHour, 14, resetsAt: now.addingTimeInterval(45 * 60), estimated: true, age: 42 * 60),
            weekly: Fixture.reading(.weekly, 89, resetsAt: sunday7pm, estimated: true, age: 42 * 60)
        )
        let guessed = model(Fixture.snapshot(plan: estimated))
        #expect(guessed.weekly.detail == "resets ~Sun 7 PM · as of 42m ago")
        #expect(guessed.weekly.accessibilityValue == "89% used, resets about Sunday 7 PM, as of 42 minutes ago")
        #expect(guessed.fiveHour.accessibilityValue == "14% used, resets in about 45 minutes, as of 42 minutes ago")

        let notStarted = PlanUsage(fiveHour: Fixture.reading(.fiveHour, 0, resetsAt: nil))
        #expect(model(Fixture.snapshot(plan: notStarted)).fiveHour.accessibilityValue == "0% used, not started")
        let unknown = PlanUsage(fiveHour: Fixture.reading(.fiveHour, 14, resetsAt: nil, estimated: true, age: 2 * 3600))
        #expect(model(Fixture.snapshot(plan: unknown)).fiveHour.accessibilityValue == "14% used, reset unknown, as of 2 hours ago")
    }

    @Test func limitRowWithoutDataSpeaksWhy() {
        // The dash is not spoken; the reason is.
        #expect(model(Fixture.snapshot(plan: .empty)).weekly.accessibilityValue == "no data yet")
        let unrecognized = model(Fixture.snapshot(plan: .empty, issues: [.desktopUsageUnrecognized]))
        #expect(unrecognized.fiveHour.accessibilityValue == "usage data not recognized")
    }

    @Test func blankNameFallsBack() {
        let row = model(Fixture.snapshot(sessions: [Fixture.session("a", .idle, name: "   ")])).sections.first?.rows.first
        #expect(row?.name == "Untitled session")
    }

    // MARK: Empty, access, footer

    @Test func emptyState() {
        let panel = model(Fixture.snapshot(sessions: []))
        #expect(panel.sections.isEmpty)
        #expect(panel.emptyMessage == "No Claude Code sessions running")
        #expect(panel.accessMessage == nil)
        #expect(model(Fixture.snapshot(sessions: idle(1))).emptyMessage == nil)
    }

    @Test func missingClaudeFolderAccessReplacesTheEmptyState() {
        let panel = model(Fixture.snapshot(plan: .empty, issues: [.claudeCodeFolderUnavailable, .desktopFolderUnavailable]))
        #expect(panel.accessMessage == "Headroom needs access to your Claude folders.")
        #expect(panel.emptyMessage == nil)
        #expect(model(Fixture.snapshot(issues: [.claudeCodeFolderUnavailable])).accessMessage
            == "Headroom needs access to ~/.claude to see sessions.")
    }

    @Test func unreadableRegistryDoesNotClaimThereAreNoSessions() {
        // Spec §4: an unreadable source must not be shown as a confident answer.
        let unreadable = model(Fixture.snapshot(sessions: [], issues: [.sessionRegistryUnreadable]))
        #expect(unreadable.emptyMessage == "Can't read Claude Code sessions")
        let terminalOnly = [Fixture.session("t1", .working, origin: .terminal)]
        #expect(model(Fixture.snapshot(sessions: terminalOnly, issues: [.sessionRegistryUnreadable])).emptyMessage == nil)
        // The folder prompt already explains an empty list.
        let noFolder = model(Fixture.snapshot(issues: [.claudeCodeFolderUnavailable, .sessionRegistryUnreadable]))
        #expect(noFolder.emptyMessage == nil)
    }

    @Test func missingDesktopFolderAccessKeepsSessions() {
        let panel = model(Fixture.snapshot(sessions: [], issues: [.desktopFolderUnavailable]))
        #expect(panel.accessMessage == "Headroom needs access to the Claude app's folder to read limits.")
        #expect(panel.emptyMessage == "No Claude Code sessions running")
    }

    @Test func footerNamesTheNewestSource() {
        #expect(model(Fixture.snapshot()).footer == "Updated 2m ago · from the Claude app")
        let mixed = PlanUsage(
            fiveHour: Fixture.reading(.fiveHour, 10, age: 60, source: .terminal),
            weekly: Fixture.reading(.weekly, 40, age: 600, source: .desktopApp)
        )
        #expect(model(Fixture.snapshot(plan: mixed)).footer == "Updated 1m ago · from the terminal")
        #expect(model(Fixture.snapshot(plan: .empty)).footer == "No usage data yet")
    }

    @Test func terminalMenuTitleFollowsConnection() {
        #expect(model(Fixture.snapshot(connected: false)).terminalMenuTitle == "Connect terminal")
        #expect(model(Fixture.snapshot(connected: true)).terminalMenuTitle == "Disconnect terminal")
    }
}
