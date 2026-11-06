import Foundation
import HeadroomModel
import HeadroomShare
import HeadroomUI
import Testing
@testable import HeadroomWidgetUI

/// Synthetic snapshots and files at a fixed date, formatted in UTC with a 12-hour English locale.
private struct Fixture {
    /// Thursday 2026-09-24 14:10 UTC.
    let now = Date(timeIntervalSince1970: 1_790_259_000)
    let format = HeadroomFormat(
        calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "en_US")
    )

    func plan(weekly: Double = 89, fiveHour: Double = 14, age: TimeInterval = 120, fiveHourResetsIn: TimeInterval = 3 * 3600) -> PlanUsage {
        let observedAt = now.addingTimeInterval(-age)
        return PlanUsage(
            fiveHour: LimitReading(kind: .fiveHour, usedPercent: fiveHour, resetsAt: now.addingTimeInterval(fiveHourResetsIn),
                                   resetIsEstimated: false, observedAt: observedAt, source: .desktopApp),
            weekly: LimitReading(kind: .weekly, usedPercent: weekly, resetsAt: now.addingTimeInterval(3 * 86_400),
                                 resetIsEstimated: false, observedAt: observedAt, source: .desktopApp)
        )
    }

    func codex(weekly: Double = 94, fiveHour: Double? = 20, status: ToolStatus = .ok) -> ToolUsage {
        var limits = [ToolLimit(window: .weekly, usedPercent: weekly, resetsAt: now.addingTimeInterval(5 * 86_400), observedAt: now)]
        if let fiveHour {
            limits.append(ToolLimit(window: .fiveHour, usedPercent: fiveHour, resetsAt: now.addingTimeInterval(3600), observedAt: now))
        }
        return ToolUsage(tool: .codex, limits: status == .ok ? limits : [], hasFiveHourWindow: fiveHour != nil, status: status)
    }

    func copilot(used: Double = 512, allowance: Double? = 1500, status: ToolStatus = .ok, age: TimeInterval = 600) -> ToolUsage {
        ToolUsage(tool: .copilot, limits: [ToolLimit(
            window: .monthly, usedPercent: allowance.map { used / $0 * 100 }, used: used, allowance: allowance,
            unit: .aiCredits, resetsAt: Date(timeIntervalSince1970: 1_790_812_800), // 2026-10-01 00:00 UTC
            observedAt: now.addingTimeInterval(-age)
        )], status: status)
    }

    func session(_ id: String, _ activity: SessionActivity, tool: ToolID = .claude, name: String? = nil) -> SessionInfo {
        SessionInfo(
            id: id, name: name ?? id, projectPath: "/Users/me/code/\(id)", origin: .terminal, activity: activity,
            activitySince: now, startedAt: now, pid: 7, transcriptPath: nil,
            context: ContextUsage(usedTokens: 100_000, windowTokens: 200_000, model: nil, windowIsExact: true, observedAt: now),
            tool: tool
        )
    }

    func snapshot(
        plan: PlanUsage? = nil, sessions: [SessionInfo] = [], codex: ToolUsage? = nil, copilot: ToolUsage? = nil,
        claudeTracked: Bool = true
    ) -> HeadroomSnapshot {
        HeadroomSnapshot(
            plan: plan ?? self.plan(), sessions: sessions, terminalBridgeConnected: true, issues: [], generatedAt: now,
            codex: codex, copilot: copilot, claudeTracked: claudeTracked
        )
    }

    func file(
        _ snapshot: HeadroomSnapshot, writtenAgo: TimeInterval = 120, isSample: Bool = false, pillTool: ToolID? = .claude,
        showsNames: Bool = true
    ) -> WidgetSnapshotFile {
        WidgetSnapshotFile.scrubbing(
            snapshot, writtenAt: now.addingTimeInterval(-writtenAgo), isSample: isSample, pillTool: pillTool,
            showsSessionNames: showsNames
        )
    }

    func limits(_ file: WidgetSnapshotFile?, _ choice: WidgetToolChoice = .automatic, at date: Date? = nil) -> LimitsWidgetModel {
        LimitsWidgetModel(file: file, choice: choice, now: date ?? now, format: format)
    }

    func sessions(_ file: WidgetSnapshotFile?, at date: Date? = nil) -> SessionsWidgetModel {
        SessionsWidgetModel(file: file, now: date ?? now, format: format)
    }
}

@Suite struct LimitsWidgetModelTests {
    private let f = Fixture()

    @Test func claudeOnlyShowsTheClaudeHeader() {
        let model = f.limits(f.file(f.snapshot(sessions: [f.session("a", .working), f.session("b", .idle)])))
        #expect(model.tool.tool == .claude)
        #expect(model.columns.isEmpty)
        #expect(model.tool.rows.map(\.title) == ["Weekly", "5-hour"])
        #expect(model.tool.rows.map(\.value) == ["89%", "14%"])
        #expect(model.tool.rows[0].reset == "resets Sun 2:10 PM")
        #expect(model.tool.rows[1].reset == "resets in 3h")
        #expect(model.tool.drawsInnerTrack)
        #expect(model.tool.gauge.outer?.severity == .warning)
        #expect(model.dot == .working)
        #expect(model.count == 1)
        #expect(model.footer == WidgetFooter(text: "Updated 2m ago", tone: .plain))
    }

    /// Automatic with two or more tools: a column each, in the fixed order; the single tool is the pill's.
    @Test func automaticWithSeveralToolsHasColumns() {
        let file = f.file(f.snapshot(codex: f.codex(), copilot: f.copilot()), pillTool: .codex)
        let model = f.limits(file)
        #expect(model.columns.map(\.tool) == [.claude, .codex, .copilot])
        #expect(model.tool.tool == .codex)
        #expect(model.columns[1].tightestRow?.value == "94%")
        #expect(model.columns[2].amount == "512 of 1,500 credits")
        #expect(model.columns[2].rows[0].reset == "resets Oct 1")
        #expect(!model.columns[2].drawsInnerTrack)
        // A fixed choice never shows columns.
        #expect(f.limits(file, .claude).columns.isEmpty)
    }

    /// Without the pill's tool, Automatic takes the first tracked tool with a percent, like "Rings show".
    @Test func automaticFallsBackToTheFirstToolWithAPercent() {
        let snapshot = f.snapshot(codex: f.codex(status: .noActivity), copilot: f.copilot(), claudeTracked: false)
        #expect(f.limits(f.file(snapshot, pillTool: nil)).tool.tool == .copilot)
        #expect(f.limits(f.file(snapshot, pillTool: .claude)).tool.tool == .copilot)
        #expect(f.limits(f.file(snapshot, pillTool: .codex)).tool.tool == .codex)
    }

    @Test func copilotTrackedForSessionsOnlyHasNoColumn() {
        let model = f.limits(f.file(f.snapshot(copilot: .copilotSessionsOnly)))
        #expect(model.columns.isEmpty)
        #expect(f.limits(f.file(f.snapshot(copilot: .copilotSessionsOnly)), .copilot).tool.status == "Sessions only")
    }

    @Test func aToolThatIsntTrackedSaysSo() {
        let model = f.limits(f.file(f.snapshot()), .codex)
        #expect(model.tool.tool == .codex)
        #expect(model.tool.status == "Not tracked")
        #expect(model.tool.gauge.hasNoData)
    }

    @Test func noFileIsEmptyTracksAndOpenHeadroom() {
        let model = f.limits(nil, .codex)
        #expect(model.isEmpty)
        #expect(model.tool.tool == .codex)
        #expect(model.tool.rows.isEmpty)
        #expect(model.footer == .openHeadroom)
        #expect(f.limits(nil).tool.tool == .claude)
    }

    /// Each entry rolls the limits over at its own date: the 5-hour window resets without a reload.
    @Test func entriesRollLimitsOver() {
        let file = f.file(f.snapshot(plan: f.plan(fiveHour: 60, fiveHourResetsIn: 600)))
        let later = f.limits(file, at: f.now.addingTimeInterval(900))
        #expect(later.tool.rows[1].value == "0%")
        #expect(later.tool.rows[1].reset == "not started")
    }

    @Test func staleReadingsSayHowOld() {
        let model = f.limits(f.file(f.snapshot(plan: f.plan(age: 3 * 3600))))
        #expect(model.tool.gauge.isStale)
        #expect(model.tool.rows[0].asOf == "3h ago")
        #expect(model.tool.rows[0].detail == "resets Sun 2:10 PM · as of 3h ago")
        #expect(model.tool.rows[0].shortDetail == "as of 3h ago")
    }

    /// Copilot with the plan not set: the amount, no percent, no ring fill.
    @Test func copilotWithoutAllowanceShowsTheAmount() {
        let model = f.limits(f.file(f.snapshot(copilot: f.copilot(used: 1_234.4, allowance: nil)), pillTool: .copilot), .copilot)
        let row = model.tool.rows[0]
        #expect(row.badge == nil)
        #expect(row.value == "1,234")
        #expect(row.title == "Monthly")
        #expect(row.amountLabel == "credits used")
        #expect(row.detail == "credits used · resets Oct 1")
        #expect(model.tool.amount == nil)
        #expect(model.tool.gauge.outer == nil)
    }

    /// 1.1 §14.12: a stale Codex reading that nothing has used Codex since keeps its age but isn't dimmed.
    @Test func quietCodexReadingIsNotDimmed() {
        var codex = f.codex()
        codex.limits = codex.limits.map { limit in
            var limit = limit
            limit.observedAt = f.now.addingTimeInterval(-3 * 3600)
            return limit
        }
        codex.quietSinceReading = true
        let quiet = f.limits(f.file(f.snapshot(codex: codex), pillTool: .codex), .codex)
        #expect(!quiet.tool.gauge.isStale)
        #expect(quiet.tool.rows[0].asOf == "3h ago")

        codex.quietSinceReading = nil
        #expect(f.limits(f.file(f.snapshot(codex: codex), pillTool: .codex), .codex).tool.gauge.isStale)
    }

    /// Offline keeps the last reading, dimmed, with its age even when it isn't stale yet.
    @Test func copilotOfflineKeepsTheReadingDimmed() {
        let model = f.limits(f.file(f.snapshot(copilot: f.copilot(status: .offline, age: 300))), .copilot)
        #expect(model.tool.gauge.isStale)
        #expect(model.tool.rows[0].asOf == "5m ago")
    }

    @Test func statusesWithoutNumbers() {
        #expect(f.limits(f.file(f.snapshot(copilot: ToolUsage(tool: .copilot, status: .notConnected))), .copilot).tool.status
            == "Not connected")
        #expect(f.limits(f.file(f.snapshot(copilot: f.copilot(status: .signInExpired))), .copilot).tool.status == "Sign-in expired")
        #expect(f.limits(f.file(f.snapshot(codex: f.codex(status: .noActivity))), .codex).tool.status == "No limits found")
    }

    /// Codex Pro: weekly only, so no inner track and no inner row.
    @Test func weeklyOnlyHasNoInnerRing() {
        let model = f.limits(f.file(f.snapshot(codex: f.codex(weekly: 42, fiveHour: nil))), .codex)
        #expect(!model.tool.drawsInnerTrack)
        #expect(model.tool.outerRow?.title == "Weekly")
        #expect(model.tool.innerRow == nil)
    }

    @Test func footers() {
        let snapshot = f.snapshot()
        #expect(f.limits(f.file(snapshot, isSample: true)).footer == .sample)
        #expect(f.limits(f.file(snapshot, writtenAgo: 36 * 60)).footer == .notRunning)
        #expect(f.limits(f.file(snapshot, writtenAgo: 36 * 60, isSample: true)).footer == .notRunning)
    }
}

@Suite struct SessionsWidgetModelTests {
    private let f = Fixture()

    @Test func headlineCountsWorkingAndWaiting() {
        let sessions = [f.session("w1", .working), f.session("w2", .working), f.session("n", .waitingForInput), f.session("i", .idle)]
        let model = f.sessions(f.file(f.snapshot(sessions: sessions)))
        #expect(model.headline == "2 working · 1 needs you")
        #expect(model.dot == .waiting)
        #expect(model.emptyMessage == nil)
        #expect(f.sessions(f.file(f.snapshot(sessions: [f.session("n", .waitingForInput), f.session("m", .waitingForInput)])))
            .headline == "2 need you")
        #expect(f.sessions(f.file(f.snapshot(sessions: [f.session("i", .idle)]))).headline == "1 idle")
    }

    @Test func noSessionsSaysSo() {
        let model = f.sessions(f.file(f.snapshot()))
        #expect(model.headline == "Sessions")
        #expect(model.emptyMessage == "No sessions running")
        #expect(model.rows.isEmpty)
    }

    @Test func noFileSaysOpenHeadroom() {
        let model = f.sessions(nil)
        #expect(model.isEmpty)
        #expect(model.emptyMessage == nil)
        #expect(model.footer == .openHeadroom)
    }

    /// Tool tags only when the sessions mix tools; hidden names become the tool's name, without a tag.
    @Test func toolTagsAndHiddenNames() {
        let mixed = [f.session("w", .working), f.session("codex:1", .working, tool: .codex, name: "website")]
        let tagged = f.sessions(f.file(f.snapshot(sessions: mixed)))
        #expect(tagged.rows.map(\.toolTag) == ["Claude", "Codex"])
        #expect(tagged.rows.map(\.isTerminal) == [true, true])

        let hidden = f.sessions(f.file(f.snapshot(sessions: mixed), showsNames: false))
        #expect(hidden.rows.map(\.name) == ["Claude session", "Codex session"])
        #expect(hidden.rows.allSatisfy { $0.toolTag == nil })

        let single = f.sessions(f.file(f.snapshot(sessions: [f.session("w", .working)])))
        #expect(single.rows[0].toolTag == nil)
        #expect(single.rows[0].context?.text == "50%")
    }

    @Test func sectionsGroupTheFirstRows() {
        let sessions = [f.session("w", .working), f.session("n", .waitingForInput)] + (0..<6).map { f.session("i\($0)", .idle) }
        let model = f.sessions(f.file(f.snapshot(sessions: sessions)))
        let sections = model.sections(limit: SessionsWidgetModel.largeRowLimit)
        #expect(sections.map(\.title) == ["Working", "Needs you", "Idle"])
        #expect(sections.map(\.rows.count) == [1, 1, 4])
        #expect(model.sections(limit: 1).map(\.title) == ["Working"])
        #expect(model.sections(limit: 0).isEmpty)
    }

    @Test func toolRowsForTheLargeWidget() {
        let model = f.sessions(f.file(f.snapshot(codex: f.codex(), copilot: .copilotSessionsOnly)))
        #expect(model.tools.map(\.tool) == [.claude, .codex])
    }

    @Test func outdatedWhenHeadroomStopped() {
        #expect(!f.sessions(f.file(f.snapshot(sessions: [f.session("w", .working)]))).isOutdated)
        let model = f.sessions(f.file(f.snapshot(sessions: [f.session("w", .working)]), writtenAgo: 2 * 3600))
        #expect(model.isOutdated)
        #expect(model.footer == .notRunning)
    }
}

@Suite struct WidgetToolChoiceTests {
    @Test func titlesAndTools() {
        #expect(WidgetToolChoice.allCases.map(\.title) == ["Automatic", "Claude", "Codex", "Copilot"])
        #expect(WidgetToolChoice.allCases.map(\.tool) == [nil, .claude, .codex, .copilot])
    }

    /// §14.7: the gallery says "AI usage" and "agent sessions", not "AI coding".
    @Test func galleryTexts() {
        #expect(HeadroomWidgetUI.limitsDescription == "Your AI usage limits as rings.")
        #expect(HeadroomWidgetUI.sessionsDescription == "Your agent sessions and how full their context is.")
        #expect(!(HeadroomWidgetUI.limitsDescription + HeadroomWidgetUI.sessionsDescription).contains("coding"))
    }
}

/// 1.1 §14.2: the Limits widgets' rows carry their ring for the 10 pt ring key, for two-ring tools only.
@Suite struct WidgetRingKeyTests {
    private let f = Fixture()

    @Test func rowsNameTheirRing() throws {
        let snapshot = f.snapshot(codex: f.codex(), copilot: f.copilot())
        let claude = try #require(WidgetToolSummary(tool: .claude, snapshot: snapshot, now: f.now, format: f.format))
        #expect(claude.rows.map(\.ring) == [.outer, .inner])
        let codex = try #require(WidgetToolSummary(tool: .codex, snapshot: snapshot, now: f.now, format: f.format))
        #expect(codex.rows.map(\.ring) == [.outer, .inner])
        let copilot = try #require(WidgetToolSummary(tool: .copilot, snapshot: snapshot, now: f.now, format: f.format))
        #expect(copilot.rows.map(\.ring) == [nil])
        let pro = try #require(WidgetToolSummary(
            tool: .codex, snapshot: f.snapshot(codex: f.codex(fiveHour: nil)), now: f.now, format: f.format
        ))
        #expect(pro.rows.map(\.ring) == [nil])
    }
}

/// 1.1 §14.4: a snapshot with dismissed waits applied counts them as idle in what the widgets compare.
@Suite struct WidgetDismissedWaitTests {
    private let f = Fixture()

    @Test func dismissedWaitsDontCountAsWaiting() {
        let raw = f.snapshot(sessions: [f.session("a", .waitingForInput), f.session("b", .waitingForInput), f.session("w", .working)])
        let shown = raw.applyingDismissals(["a"])
        let signature = WidgetSignature(snapshot: shown, isSample: false, pillTool: .claude, showsSessionNames: true)
        #expect(WidgetSignature(snapshot: raw, isSample: false, pillTool: .claude, showsSessionNames: true).waitingCount == 2)
        #expect(signature.waitingCount == 1)
        #expect(signature.activeCount == 2)
        #expect(f.sessions(f.file(shown)).rows.filter { $0.dot == .waiting }.count == 1)
    }
}
