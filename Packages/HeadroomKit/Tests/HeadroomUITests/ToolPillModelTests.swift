import Foundation
import HeadroomModel
import Testing
@testable import HeadroomUI

/// The multi-tool pill (1.1 §6.1, §6.2).
@Suite struct ToolPillModelTests {
    let now = Fixture.now

    private func pill(
        _ snapshot: HeadroomSnapshot, moment: Moment? = nil, tool: ToolID? = nil, gaugePerTool: Bool = false
    ) -> PillModel {
        PillModel(snapshot: snapshot, moment: moment, now: now, tool: tool, gaugePerTool: gaugePerTool)
    }

    // MARK: Rings show

    @Test func automaticIsClaudeWhenClaudeHasData() {
        let snapshot = Fixture.tools(codex: Fixture.codex(), copilot: Fixture.copilot())
        #expect(RingsTool.automatic(in: snapshot) == .claude)
        #expect(pill(snapshot).tool == .claude)
    }

    @Test func automaticSkipsToolsWithoutAPercent() {
        // Claude tracked with no reading, Copilot without a plan (no percent): Codex is the first with a percent.
        let snapshot = Fixture.tools(claude: .empty, codex: Fixture.codex(), copilot: Fixture.copilot(allowance: nil))
        #expect(RingsTool.automatic(in: snapshot) == .codex)
        let noPercent = Fixture.tools(claude: nil, codex: Fixture.codex(status: .noActivity).withoutLimits, copilot: Fixture.copilot(allowance: nil))
        #expect(RingsTool.automatic(in: noPercent) == .codex, "none has a percent: the first tracked tool")
    }

    @Test func automaticNeverFollowsTheTightestTool() {
        let snapshot = Fixture.tools(claude: Fixture.plan(weekly: 10, fiveHour: 5), codex: Fixture.codex(weekly: 99))
        #expect(RingsTool.automatic(in: snapshot) == .claude)
    }

    @Test func aChoiceThatIsNotTrackedFallsBackToAutomatic() {
        let snapshot = Fixture.tools(codex: Fixture.codex())
        #expect(RingsTool.resolve(.codex, in: snapshot) == .codex)
        #expect(RingsTool.resolve(.copilot, in: snapshot) == .claude)
        #expect(RingsTool.resolve(nil, in: Fixture.tools(claude: nil)) == nil)
    }

    @Test func claudeOnlyPillIsOnePointOhWhateverTheChoice() {
        let snapshot = Fixture.snapshot(plan: Fixture.plan(weekly: 89, fiveHour: 14), sessions: [Fixture.session("a", .working)])
        let plain = PillModel(snapshot: snapshot, moment: nil, now: now)
        #expect(pill(snapshot, tool: .codex, gaugePerTool: true) == plain)
        #expect(plain.tool == .claude)
        #expect(plain.toolGauges.isEmpty)
        #expect(plain.toolTip == nil)
        #expect(!plain.marksGaugeTool, "the 1.0 pill's ring has no tool symbol")
        #expect(plain.accessibilityLabel == "1 active session. Weekly 89%, 5-hour 14%.")
    }

    // MARK: Rings

    @Test func weeklyOnlyToolDrawsOneRingAndNoInnerTrack() {
        let model = pill(Fixture.tools(claude: nil, codex: Fixture.codex(weekly: 42, fiveHour: nil)))
        #expect(model.tool == .codex)
        #expect(model.gauge.outer == GaugeModel.Ring(fraction: 0.42, severity: .normal))
        #expect(model.gauge.inner == nil)
        #expect(!model.gauge.showsInnerTrack)
        #expect(!model.hasNoData)
    }

    @Test func fiveHourToolDrawsBothRings() {
        let gauge = pill(Fixture.tools(codex: Fixture.codex()), tool: .codex).gauge
        #expect(gauge.outer == GaugeModel.Ring(fraction: 0.94, severity: .warning))
        #expect(gauge.inner == GaugeModel.Ring(fraction: 0.2, severity: .normal))
        #expect(gauge.showsInnerTrack)
    }

    @Test func copilotWithoutAPlanShowsTracksOnly() {
        let model = pill(Fixture.tools(claude: nil, copilot: Fixture.copilot(allowance: nil)))
        #expect(model.tool == .copilot)
        #expect(model.hasNoData)
        #expect(!model.gauge.showsInnerTrack)
        #expect(model.badge == nil)
    }

    @Test func copilotRingIsItsPercentOfTheAllowance() {
        let gauge = pill(Fixture.tools(claude: nil, copilot: Fixture.copilot(used: 1_200))).gauge
        #expect(gauge.outer == GaugeModel.Ring(fraction: 0.8, severity: .warning))
    }

    @Test func staleOrOfflineToolDims() {
        #expect(pill(Fixture.tools(codex: Fixture.codex(age: 31 * 60)), tool: .codex).isStale)
        #expect(!pill(Fixture.tools(codex: Fixture.codex(age: 29 * 60)), tool: .codex).isStale)
        // Copilot goes stale after 45 minutes, and a reading kept while offline is dimmed at once.
        #expect(!pill(Fixture.tools(copilot: Fixture.copilot(age: 40 * 60)), tool: .copilot).isStale)
        #expect(pill(Fixture.tools(copilot: Fixture.copilot(status: .offline, age: 60)), tool: .copilot).isStale)
    }

    // MARK: Number, dot and count

    @Test func numberIsTheShownToolsTightestFromSeventyFive() {
        let snapshot = Fixture.tools(claude: Fixture.plan(weekly: 40, fiveHour: 10), codex: Fixture.codex(weekly: 94))
        #expect(pill(snapshot).badge == nil, "Claude is shown, and it is below 75 %")
        #expect(pill(snapshot, tool: .codex).badge == PercentBadge(text: "94%", severity: .warning))
        #expect(pill(Fixture.tools(codex: Fixture.codex(weekly: 60)), tool: .codex).badge == nil)
    }

    @Test func dotAndCountCoverEveryTool() {
        let sessions = [
            Fixture.toolSession("a", .working, tool: .claude),
            Fixture.toolSession("b", .working, tool: .codex),
            Fixture.toolSession("c", .waitingForInput, tool: .copilot),
            Fixture.toolSession("d", .idle, tool: .codex),
        ]
        let model = pill(Fixture.tools(codex: Fixture.codex(), copilot: Fixture.copilot(), sessions: sessions), tool: .codex)
        #expect(model.count == 3)
        #expect(model.dot == .waiting)
    }

    // MARK: One gauge per tool

    @Test func oneGaugePerToolInDisplayOrder() {
        let snapshot = Fixture.tools(codex: Fixture.codex(), copilot: Fixture.copilot())
        let model = pill(snapshot, gaugePerTool: true)
        #expect(model.isGaugePerTool)
        #expect(model.toolGauges.map(\.tool) == [.claude, .codex, .copilot])
        #expect(model.toolGauges[2].gauge.showsInnerTrack == false)
        #expect(model.toolGauges.map(\.badge) == [nil, PercentBadge(text: "94%", severity: .warning), nil])
        #expect(model.marksGaugeTool, "with two or more tools, each gauge carries its tool's symbol")
        #expect(pill(snapshot, tool: .codex).marksGaugeTool, "so does the one gauge 'Rings show' picks")
    }

    @Test func gaugesSkipToolsWithoutLimits() {
        let snapshot = Fixture.tools(codex: Fixture.codex(), copilot: Fixture.copilot(status: .notConnected))
        #expect(pill(snapshot, gaugePerTool: true).toolGauges.map(\.tool) == [.claude, .codex])
        // With a single tool left, it is the ordinary pill.
        let single = Fixture.tools(codex: Fixture.codex(status: .noActivity).withoutLimits)
        #expect(!pill(single, gaugePerTool: true).isGaugePerTool)
    }

    @Test func noNumberBelowSeventyFiveAndTiedWarningsBothShow() {
        let calm = Fixture.tools(claude: Fixture.plan(weekly: 40, fiveHour: 10), codex: Fixture.codex(weekly: 30, fiveHour: 5))
        let model = pill(calm, gaugePerTool: true)
        #expect(model.badge == nil)
        #expect(model.toolGauges.allSatisfy { $0.badge == nil })
        let tie = Fixture.tools(claude: Fixture.plan(weekly: 90, fiveHour: 10), codex: Fixture.codex(weekly: 90, fiveHour: 5))
        #expect(pill(tie, gaugePerTool: true).toolGauges.map(\.badge?.text) == ["90%", "90%"])
    }

    @Test func everyToolShowsItsOwnTightestWarningOrCriticalPercentage() {
        let snapshot = Fixture.tools(
            claude: Fixture.plan(weekly: 94, fiveHour: 10),
            codex: Fixture.codex(weekly: 40, fiveHour: 85),
            copilot: Fixture.copilot(used: 100, allowance: 100)
        )
        #expect(pill(snapshot, gaugePerTool: true).toolGauges.map(\.badge) == [
            PercentBadge(text: "94%", severity: .warning),
            PercentBadge(text: "85%", severity: .warning),
            PercentBadge(text: "100%", severity: .critical)
        ])
    }

    @Test func perToolBadgeUsesTheSameRoundedThresholdAsItsRing() {
        let snapshot = Fixture.tools(
            claude: Fixture.plan(weekly: 74.4, fiveHour: 10),
            codex: Fixture.codex(weekly: 74.5),
            copilot: Fixture.copilot(used: .nan, allowance: 100)
        )
        let gauges = pill(snapshot, gaugePerTool: true).toolGauges
        #expect(gauges.map(\.badge?.text) == [nil, "75%", nil])
        #expect(gauges[1].gauge.outer?.severity == gauges[1].badge?.severity)
    }

    @Test func eachGaugeDimsOnItsOwnTool() {
        let snapshot = Fixture.tools(codex: Fixture.codex(age: 3 * 3600), copilot: Fixture.copilot())
        let gauges = pill(snapshot, gaugePerTool: true).toolGauges
        #expect(gauges.map(\.gauge.isStale) == [false, true, false])
    }

    // MARK: Accessibility

    @Test func multiToolLabelNamesEveryTool() {
        let sessions = (1...3).map { Fixture.toolSession("s\($0)", .working, tool: .claude) }
        let snapshot = Fixture.tools(
            claude: Fixture.plan(weekly: 89, fiveHour: 14), codex: Fixture.codex(weekly: 94, fiveHour: nil),
            copilot: Fixture.copilot(), sessions: sessions
        )
        let model = pill(snapshot)
        #expect(model.accessibilityLabel == "3 active sessions. Claude weekly 89%, 5-hour 14%. Codex weekly 94%. Copilot 34% of monthly credits.")
        #expect(model.toolTip == "Claude weekly 89%, 5-hour 14%. Codex weekly 94%. Copilot 34% of monthly credits.")
    }

    @Test func multiToolLabelSaysWhatIsMissing() {
        let snapshot = Fixture.tools(
            claude: nil, codex: Fixture.codex(age: 2 * 3600), copilot: Fixture.copilot(status: .notConnected),
            sessions: [Fixture.toolSession("w", .waitingForInput, tool: .codex)]
        )
        #expect(pill(snapshot).accessibilityLabel
            == "1 active session, 1 needs input. Codex weekly 94%, 5-hour 20%, out of date. Copilot: Connect GitHub in Settings.")
        let noPlan = Fixture.tools(claude: nil, copilot: Fixture.copilot(allowance: nil))
        #expect(pill(noPlan).toolTip == "Copilot 512 credits used this month.")
    }

    @Test func sessionMomentNamesItsToolForVoiceOverOnly() {
        let snapshot = Fixture.tools(codex: Fixture.codex())
        let model = pill(snapshot, moment: .sessionFinished(sessionID: "codex:abc", name: "ledger"))
        #expect(model.moment?.text == "ledger finished")
        #expect(model.accessibilityLabel.hasPrefix("Codex session ledger finished. "))
        let claudeOnly = PillModel(snapshot: Fixture.snapshot(), moment: .sessionFinished(sessionID: "a", name: "ledger"), now: now)
        #expect(claudeOnly.accessibilityLabel.hasPrefix("ledger finished. "))
    }
}

extension ToolUsage {
    /// The same tool with no readings at all.
    var withoutLimits: ToolUsage {
        var usage = self
        usage.limits = []
        return usage
    }
}
