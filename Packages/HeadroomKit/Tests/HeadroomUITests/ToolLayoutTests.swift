import AppKit
import HeadroomModel
import SwiftUI
import Testing
@testable import HeadroomUI

/// Measured multi-tool layout (1.1 §6.1, §6.3).
@MainActor @Suite struct ToolLayoutTests {
    let now = Fixture.now

    /// At 1.0's 22 pt height, where the spec's widths were measured.
    private func pillWidth(_ snapshot: HeadroomSnapshot, tool: ToolID? = nil, gaugePerTool: Bool = false) -> CGFloat {
        NSHostingView(rootView: PillView(
            snapshot: snapshot, moment: nil, now: now, tool: tool, gaugePerTool: gaugePerTool, height: PillMetrics.minimumHeight
        ))
        .fittingSize.width
    }

    @Test func eachExtraGaugeAddsTwentyThreePoints() {
        let sessions = (1...3).map { Fixture.toolSession("s\($0)", .working, tool: .claude) }
        let calm = Fixture.tools(
            claude: Fixture.plan(weekly: 40, fiveHour: 10), codex: Fixture.codex(weekly: 30, fiveHour: 5),
            copilot: Fixture.copilot(used: 100), sessions: sessions
        )
        let single = pillWidth(calm)
        let perTool = pillWidth(calm, gaugePerTool: true)
        #expect(abs(perTool - single - 2 * 23) < 0.5, "\(single) → \(perTool)")
    }

    @Test(arguments: [ToolID.codex, .copilot])
    func everyWarningGaugeReservesSpaceForItsOwnPercentage(tool: ToolID) {
        func snapshot(percent: Double) -> HeadroomSnapshot {
            Fixture.tools(
                claude: Fixture.plan(weekly: 94, fiveHour: 10),
                codex: Fixture.codex(weekly: tool == .codex ? percent : 40),
                copilot: Fixture.copilot(used: tool == .copilot ? percent : 40, allowance: 100)
            )
        }
        let calm = pillWidth(snapshot(percent: 74), gaugePerTool: true)
        let warning = pillWidth(snapshot(percent: 85), gaugePerTool: true)
        #expect(warning - calm >= 24,
                "\(tool) must show its percentage even while Claude has a higher warning percentage.")
    }

    /// The spec estimates about 143 pt: with "100%" after the middle gauge (and its 2 pt before the next gauge) and a
    /// one-digit count it is 151 pt; a two-digit count adds about 8 pt, as it does to the 1.0 pill.
    @Test func threeGaugesAndTheWidestNumberStayNearTheBudget() {
        let sessions = (1...9).map { Fixture.toolSession("s\($0)", .working, tool: .claude) }
        let full = Fixture.tools(
            claude: Fixture.plan(weekly: 40, fiveHour: 10), codex: Fixture.codex(weekly: 100, fiveHour: 5),
            copilot: Fixture.copilot(used: 100), sessions: sessions
        )
        let width = pillWidth(full, gaugePerTool: true)
        #expect(width <= 152, "\(width) pt")
    }

    @Test func singleRingPillIsAsWideAsTheTwoRingPill() {
        let pro = Fixture.tools(claude: nil, codex: Fixture.codex(weekly: 42, fiveHour: nil))
        let plus = Fixture.tools(claude: nil, codex: Fixture.codex(weekly: 42, fiveHour: 10))
        #expect(pillWidth(pro) == pillWidth(plus))
    }

    @Test func multiToolPanelKeepsItsWidth() {
        let snapshot = Fixture.tools(
            codex: Fixture.codex(), copilot: Fixture.copilot(used: 1_620_000, allowance: 1_500_000, extra: 120_000),
            sessions: [Fixture.toolSession("a", .working, tool: .claude), Fixture.toolSession("b", .idle, tool: .codex)]
        )
        let view = NSHostingView(rootView: PanelView(snapshot: snapshot, now: now, actions: .none))
        #expect(view.fittingSize.width == 360)
    }
}
