import Foundation
import HeadroomModel
import Testing
@testable import HeadroomUI

/// The multi-tool panel (1.1 §4.6, §6.3).
@Suite struct ToolPanelModelTests {
    let now = Fixture.now

    private func panel(_ snapshot: HeadroomSnapshot, tool: ToolID? = nil, showsCodexOffer: Bool = false) -> PanelModel {
        PanelModel(snapshot: snapshot, now: now, tool: tool, showsCodexOffer: showsCodexOffer, format: Fixture.usFormat)
    }

    // MARK: Header

    @Test func claudeOnlyHeaderIsOnePointOh() {
        let model = panel(Fixture.snapshot(plan: Fixture.plan(weekly: 89, fiveHour: 14, extra: 12)))
        #expect(model.header.tool == .claude)
        #expect(model.header.toolName == nil)
        #expect(model.header.rows == [model.weekly, model.fiveHour])
        #expect(model.header.notes == ["Extra usage 12%"])
        #expect(model.header.gauge == model.gauge)
        #expect(model.toolRows.isEmpty)
        #expect(model.footer == "Updated 2m ago · from the Claude app")
    }

    @Test func multiToolHeaderNamesItsToolAndOtherToolsGetCompactRows() {
        let model = panel(Fixture.tools(codex: Fixture.codex(), copilot: Fixture.copilot()))
        #expect(model.header.tool == .claude)
        #expect(model.header.toolName == "Claude")
        #expect(model.toolRows.map(\.name) == ["Codex", "Copilot"])
        #expect(model.footer == "Updated 2m ago")
    }

    @Test func headerFollowsRingsShow() {
        let model = panel(Fixture.tools(codex: Fixture.codex(), copilot: Fixture.copilot()), tool: .codex)
        #expect(model.header.tool == .codex)
        #expect(model.header.toolName == "Codex")
        #expect(model.header.rows.map(\.title) == ["Weekly", "5-hour"])
        #expect(model.header.rows.map(\.detail) == ["resets Wed 9 AM", "resets in 1h 10m"])
        #expect(model.toolRows.map(\.name) == ["Claude", "Copilot"])
        #expect(model.footer == "Updated 5m ago", "the header tool's newest reading")
    }

    @Test func singleToolHeadersNameTheirSource() {
        let codex = panel(Fixture.tools(claude: nil, codex: Fixture.codex(weekly: 42, fiveHour: nil)))
        #expect(codex.header.toolName == nil)
        #expect(codex.header.rows.count == 1, "a single-window tool: one row")
        #expect(codex.footer == "Updated 5m ago · from Codex")
        let copilot = panel(Fixture.tools(claude: nil, copilot: Fixture.copilot()))
        #expect(copilot.footer == "Updated 10m ago · from GitHub")
        #expect(panel(Fixture.tools(claude: nil, copilot: Fixture.copilot(status: .notConnected))).footer == "No usage data yet")
    }

    @Test func copilotHeaderAddsItsAmount() {
        let row = panel(Fixture.tools(claude: nil, copilot: Fixture.copilot())).header.rows[0]
        #expect(row.title == "Monthly")
        #expect(row.badge == PercentBadge(text: "34%", severity: .normal))
        #expect(row.detail == "resets Oct 1")
        #expect(row.lines == ["512 of 1,500 credits"])
        #expect(row.accessibilityValue == "34% used, resets October 1, 512 of 1,500 credits")

        let extra = panel(Fixture.tools(claude: nil, copilot: Fixture.copilot(used: 1_620, extra: 120))).header.rows[0]
        #expect(extra.lines == ["1,620 of 1,500 credits · 120 extra billed"])
        #expect(extra.badge?.text == "100%")
    }

    @Test func copilotWithoutAPlanShowsUsageOnly() {
        let row = panel(Fixture.tools(claude: nil, copilot: Fixture.copilot(allowance: nil, extra: 120))).header.rows[0]
        #expect(row.badge == nil)
        #expect(row.detail == "512 credits used · resets Oct 1")
        #expect(row.lines == ["120 extra billed"])
        let requests = panel(Fixture.tools(claude: nil, copilot: Fixture.copilot(used: 120, allowance: 300, unit: .premiumRequests)))
        #expect(requests.header.rows[0].lines == ["120 of 300 requests"])
    }

    @Test func toolHeaderWithNothingToCountShowsItsStatus() {
        let notConnected = panel(Fixture.tools(claude: nil, copilot: Fixture.copilot(status: .notConnected))).header
        #expect(notConnected.rows.isEmpty)
        #expect(notConnected.status == ToolStatusLine(message: "Connect GitHub in Settings", action: .openToolsSettings))
        #expect(notConnected.status?.actionTitle == "Settings…")
        #expect(!notConnected.gauge.showsInnerTrack)
        let expired = panel(Fixture.tools(claude: nil, copilot: Fixture.copilot(status: .signInExpired))).header
        #expect(expired.status == ToolStatusLine(message: "Sign-in expired", action: .reconnectGitHub))
        #expect(expired.status?.actionTitle == "Reconnect")
    }

    @Test func dimmedToolRowsSayHowOld() {
        let row = panel(Fixture.tools(claude: nil, copilot: Fixture.copilot(status: .offline, age: 2 * 3600))).header.rows[0]
        #expect(row.detail == "resets Oct 1 · as of 2h ago")
    }

    // MARK: Compact rows (exact copy, 1.1 §6.3 and §4.6)

    private func row(codex: ToolUsage? = nil, copilot: ToolUsage? = nil) throws -> PanelModel.ToolRow {
        try #require(panel(Fixture.tools(codex: codex, copilot: copilot)).toolRows.first)
    }

    @Test func codexCompactRow() throws {
        let codex = try row(codex: Fixture.codex())
        #expect(codex.lines == [
            .init(label: "Weekly", percent: "94%", severity: .warning, detail: "resets Wed 9 AM", ring: .outer),
            .init(label: "5-hour", percent: "20%", severity: .normal, detail: "resets in 1h 10m", ring: .inner),
        ])
        #expect(codex.notes.isEmpty)
        #expect(codex.status == nil)
        #expect(codex.gauge.showsInnerTrack)
        #expect(codex.helpText == "Plus plan\nWeekly resets Sep 30, 2026 at 9:00 AM\n5-hour resets Sep 24, 2026 at 3:20 PM\nAs of 5m ago")
        #expect(codex.accessibilityLabel == "Codex limits")
        #expect(codex.accessibilityValue == "weekly 94% used, resets Wednesday 9 AM; 5-hour 20% used, resets in 1 hour 10 minutes")
    }

    @Test func codexCompactRowStates() throws {
        #expect(try row(codex: ToolUsage(tool: .codex, status: .noActivity)).status?.message == "No Codex limits found")
        #expect(try row(codex: ToolUsage(tool: .codex, status: .needsAccess)).status?.message == "No access to ~/.codex")

        let stale = try row(codex: Fixture.codex(age: 3 * 3600))
        #expect(stale.lines.map(\.detail) == ["as of 3h ago", "resets in 1h 10m"])
        #expect(stale.gauge.isStale)

        // 1.1 §14.12: nothing has used Codex since the reading: it keeps its age but isn't dimmed.
        var quietUsage = Fixture.codex(age: 3 * 3600)
        quietUsage.quietSinceReading = true
        let quiet = try row(codex: quietUsage)
        #expect(quiet.lines.map(\.detail) == ["as of 3h ago", "resets in 1h 10m"])
        #expect(!quiet.gauge.isStale)
        #expect(quiet.accessibilityValue.hasSuffix("as of 3 hours ago"))

        var past = Fixture.codex(weekly: 0, fiveHour: nil, age: 26 * 3600)
        past.limits[0].resetsAt = nil
        past.limits[0].resetSinceReading = true
        #expect(try row(codex: past).lines == [.init(label: "Weekly", percent: "0%", severity: .normal, detail: "reset since last reading")])

        var spark = Fixture.codex(weekly: 42, fiveHour: nil)
        spark.otherBuckets = [NamedLimits(id: "codex_bengalfox", name: "GPT-5.3-Codex-Spark", limits: [Fixture.limit(.weekly, 80)])]
        #expect(try row(codex: spark).notes == ["GPT-5.3-Codex-Spark · weekly 80%"])
        spark.otherBuckets[0].limits = [Fixture.limit(.weekly, 74)]
        #expect(try row(codex: spark).notes.isEmpty, "only buckets at 75 % or more")
    }

    @Test func copilotCompactRowStates() throws {
        let ok = try row(copilot: Fixture.copilot())
        #expect(ok.lines == [.init(label: "Monthly", percent: "34%", severity: .normal, detail: "resets Oct 1")])
        #expect(ok.notes == ["512 of 1,500 credits"])
        #expect(!ok.gauge.showsInnerTrack)

        let noPlan = try row(copilot: Fixture.copilot(allowance: nil))
        #expect(noPlan.lines == [.init(label: "Monthly", percent: "", severity: .normal, detail: "resets Oct 1")])
        #expect(noPlan.notes == ["512 credits used"])

        #expect(try row(copilot: Fixture.copilot(extra: 120)).notes == ["512 of 1,500 credits · 120 extra billed"])
        #expect(try row(copilot: Fixture.copilot(status: .notConnected)).status
            == ToolStatusLine(message: "Connect GitHub in Settings", action: .openToolsSettings))
        let noUsage = try row(copilot: Fixture.copilot(status: .noIndividualUsage))
        #expect(noUsage.status == ToolStatusLine(message: "No usage billed to you this month"))
        #expect(noUsage.helpText == "Pro plan · @octocat\nPlans paid by an organization can't be read.")
        var longLogin = Fixture.copilot(status: .noIndividualUsage)
        longLogin.account = String(repeating: "x", count: 39)
        #expect(try row(copilot: longLogin).status == noUsage.status, "a long login cut the message short")
        #expect(try row(copilot: Fixture.copilot(status: .notConnected)).helpText == nil)
        #expect(try row(copilot: Fixture.copilot(status: .signInExpired)).status
            == ToolStatusLine(message: "Sign-in expired", action: .reconnectGitHub))
        #expect(try row(copilot: ToolUsage(tool: .copilot, status: .unrecognized)).status?.message
            == "Copilot usage in an unknown format", "items only in units CopilotKit doesn't know (1.1 §4.4)")

        let offline = try row(copilot: Fixture.copilot(status: .offline, age: 2 * 3600))
        #expect(offline.lines.map(\.detail) == ["as of 2h ago"])
        #expect(offline.gauge.isStale)
        let rateLimited = try row(copilot: Fixture.copilot(status: .rateLimited, age: 60))
        #expect(rateLimited.gauge.isStale, "the kept reading is dimmed at once")
    }

    @MainActor @Test func settingsNextToConnectGitHubOpensTheToolsTab() {
        var opened: [String] = []
        let actions = PanelActions(openSettings: { opened.append("settings") }, openToolsSettings: { opened.append("tools") })
        actions.perform(.openToolsSettings)
        #expect(opened == ["tools"])

        var fallback: [String] = []
        PanelActions(openSettings: { fallback.append("settings") }).perform(.openToolsSettings)
        #expect(fallback == ["settings"], "without its own action, the gear menu's Settings… opens")
    }

    @Test func copilotTrackedForSessionsOnlyHasNoRow() {
        let model = panel(Fixture.tools(codex: Fixture.codex(), copilot: .copilotSessionsOnly))
        #expect(model.toolRows.map(\.tool) == [.codex])
    }

    @Test func claudeCompactRowUnderAnotherTool() throws {
        let model = panel(Fixture.tools(claude: Fixture.plan(weekly: 89, fiveHour: 14), codex: Fixture.codex()), tool: .codex)
        let claude = try #require(model.toolRows.first)
        #expect(claude.name == "Claude")
        #expect(claude.lines.map(\.label) == ["Weekly", "5-hour"])
        #expect(claude.lines.map(\.percent) == ["89%", "14%"])
        let empty = panel(Fixture.tools(claude: .empty, codex: Fixture.codex()), tool: .codex)
        #expect(empty.toolRows.first?.status?.message == "No usage data yet")
    }

    // MARK: Access, offer, sessions

    @Test func accessMessagesMergeCodex() {
        #expect(panel(Fixture.tools(codex: ToolUsage(tool: .codex, status: .needsAccess), issues: [.codexFolderUnavailable])).accessMessage
            == "Headroom needs access to ~/.codex to see Codex.")
        #expect(panel(Fixture.tools(issues: [.claudeCodeFolderUnavailable, .codexFolderUnavailable])).accessMessage
            == "Headroom needs access to your Claude and Codex folders.")
        #expect(panel(Fixture.tools(issues: [.desktopFolderUnavailable, .codexFolderUnavailable])).accessMessage
            == "Headroom needs access to your Claude and Codex folders.")
        #expect(panel(Fixture.snapshot(issues: [.claudeCodeFolderUnavailable])).accessMessage
            == "Headroom needs access to ~/.claude to see sessions.")
    }

    @Test func codexOfferOnlyWhenTheAppAsks() {
        #expect(panel(Fixture.snapshot()).codexOffer == nil)
        #expect(panel(Fixture.snapshot(), showsCodexOffer: true).codexOffer
            == "Codex found on this Mac. Show its limits and sessions here too?")
    }

    @Test func toolTagsRemainWhenOnlyOneTrackedToolHasSessions() {
        let mixed = panel(Fixture.tools(codex: Fixture.codex(), sessions: [
            Fixture.toolSession("a", .working, tool: .claude, name: "ledger"),
            Fixture.toolSession("b", .working, tool: .codex, name: "website"),
        ]))
        let rows = mixed.sections.flatMap(\.rows)
        #expect(rows.map(\.toolTag) == ["Claude", "Codex"])
        #expect(mixed.sessionTools == [.claude, .codex])
        #expect(rows[1].accessibilityLabel == "website, Codex, working")

        let codexOnly = panel(Fixture.tools(codex: Fixture.codex(), sessions: [Fixture.toolSession("b", .working, tool: .codex)]))
        #expect(codexOnly.sections.flatMap(\.rows).map(\.toolTag) == ["Codex"], "two tools tracked, one in the list")
        #expect(codexOnly.sessionTools == [.codex])
    }

    @Test(arguments: ToolID.allCases)
    func everySessionKeepsItsToolIconWithMultipleToolsTracked(tool: ToolID) {
        let sessions = [SessionActivity.working, .waitingForInput, .idle].enumerated().map {
            Fixture.toolSession("s\($0.offset)", $0.element, tool: tool)
        }
        let model = panel(Fixture.tools(codex: Fixture.codex(), copilot: Fixture.copilot(), sessions: sessions))
        #expect(model.sections.flatMap(\.rows).map(\.toolTag) == Array(repeating: tool.shortName, count: 3))
    }

    @Test func sessionLegendIncludesCollapsedToolsOnceInDisplayOrder() {
        let sessions = (1...5).map { Fixture.toolSession("c\($0)", .idle, tool: .claude) }
            + [Fixture.toolSession("x", .idle, tool: .codex), Fixture.toolSession("p", .idle, tool: .copilot)]
        let model = panel(Fixture.tools(codex: Fixture.codex(), copilot: Fixture.copilot(), sessions: sessions))
        #expect(model.sections.flatMap(\.rows).count == PanelModel.collapsedIdleCount)
        #expect(model.sessionTools == [.claude, .codex, .copilot])
        #expect(panel(Fixture.tools(codex: Fixture.codex(), copilot: Fixture.copilot())).sessionTools.isEmpty)
    }

    @Test func emptyListCopy() {
        #expect(panel(Fixture.snapshot()).emptyMessage == "No Claude Code sessions running")
        #expect(panel(Fixture.tools(claude: nil, codex: Fixture.codex())).emptyMessage == "No Codex sessions running")
        #expect(panel(Fixture.tools(codex: Fixture.codex())).emptyMessage == "No sessions running")
        #expect(panel(Fixture.tools(claude: nil, codex: Fixture.codex(), copilot: Fixture.copilot())).emptyMessage == "No sessions running")
    }

    @Test func unreadableCodexSessionsAreSaid() {
        let empty = panel(Fixture.tools(codex: Fixture.codex(), issues: [.codexSessionsUnreadable]))
        #expect(empty.emptyMessage == "Can't read Codex sessions")
        let listed = panel(Fixture.tools(
            codex: Fixture.codex(), sessions: [Fixture.toolSession("a", .working, tool: .claude)], issues: [.codexSessionsUnreadable]
        ))
        #expect(listed.emptyMessage == nil)
        #expect(listed.sessionNotice == "Can't read Codex sessions")
        #expect(panel(Fixture.snapshot(sessions: [Fixture.session("a", .working)], issues: [.sessionRegistryUnreadable])).sessionNotice == nil)
    }

    @Test func noEmptyMessageWhileEveryFolderWaitsForAccess() {
        let blocked = Fixture.tools(
            claude: .empty, codex: ToolUsage(tool: .codex, status: .needsAccess),
            issues: [.claudeCodeFolderUnavailable, .desktopFolderUnavailable, .codexFolderUnavailable]
        )
        #expect(panel(blocked).emptyMessage == nil)
        #expect(panel(blocked).accessMessage != nil)
    }

    @Test func sampleDataFooterWinsOverTools() {
        let model = PanelModel(snapshot: Fixture.tools(codex: Fixture.codex()), now: now, sampleData: .showing)
        #expect(model.footer == "Sample data")
    }
}
