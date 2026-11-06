import Foundation
import HeadroomModel
import Testing
@testable import HeadroomShare

@Suite struct WidgetSignatureTests {
    private let now = Date(timeIntervalSince1970: 1_790_250_000)

    private func plan(weekly: Double, fiveHour: Double = 10) -> PlanUsage {
        PlanUsage(
            fiveHour: LimitReading(kind: .fiveHour, usedPercent: fiveHour, resetsAt: nil, resetIsEstimated: false,
                                   observedAt: now, source: .terminal),
            weekly: LimitReading(kind: .weekly, usedPercent: weekly, resetsAt: nil, resetIsEstimated: false,
                                 observedAt: now, source: .terminal)
        )
    }

    private func session(_ id: String, _ activity: SessionActivity, used: Int = 50_000) -> SessionInfo {
        SessionInfo(
            id: id, name: id, projectPath: "/Users/me/\(id)", origin: .terminal, activity: activity,
            activitySince: now, startedAt: now, pid: 42, transcriptPath: nil,
            context: ContextUsage(usedTokens: used, windowTokens: 200_000, model: nil, windowIsExact: true, observedAt: now)
        )
    }

    private func signature(
        _ plan: PlanUsage, _ sessions: [SessionInfo] = [], codex: ToolUsage? = nil, isSample: Bool = false
    ) -> WidgetSignature {
        WidgetSignature(
            snapshot: HeadroomSnapshot(plan: plan, sessions: sessions, terminalBridgeConnected: true, issues: [],
                                       generatedAt: now, codex: codex),
            isSample: isSample, pillTool: .claude, showsSessionNames: true
        )
    }

    @Test func percentsAreRoundedAndJudgedLikeTheUI() {
        let sig = signature(plan(weekly: 74.6))
        #expect(sig.tools.map(\.tool) == [.claude])
        #expect(sig.tools[0].limits.map(\.window) == [.weekly, .fiveHour])
        #expect(sig.tools[0].limits[0] == WidgetSignature.Limit(window: .weekly, percent: 75, severity: .warning))
        // Moving within a rounded percent changes nothing.
        #expect(signature(plan(weekly: 42.2)) == signature(plan(weekly: 41.8)))
        #expect(signature(plan(weekly: 42.2)) != signature(plan(weekly: 43.1)))
    }

    @Test func copilotWithoutAllowanceHasNoPercent() {
        let copilot = ToolUsage(tool: .copilot, limits: [
            ToolLimit(window: .monthly, usedPercent: nil, used: 512, unit: .aiCredits, resetsAt: nil, observedAt: now),
        ], status: .ok)
        let sig = WidgetSignature(
            snapshot: HeadroomSnapshot(plan: .empty, sessions: [], terminalBridgeConnected: false, issues: [],
                                       generatedAt: now, copilot: copilot, claudeTracked: false),
            isSample: false, pillTool: .copilot, showsSessionNames: true
        )
        #expect(sig.tools == [WidgetSignature.Tool(tool: .copilot, status: .ok, limits: [
            WidgetSignature.Limit(window: .monthly, percent: nil, severity: nil),
        ])])
    }

    @Test func sessionsAreCountedAndTheTopSevenKept() {
        let sessions = [session("w", .working), session("n", .waitingForInput)]
            + (0..<8).map { session("i\($0)", .idle) }
        let sig = signature(plan(weekly: 40), sessions)
        #expect(sig.activeCount == 2)
        #expect(sig.waitingCount == 1)
        #expect(sig.topSessions.map(\.id) == ["w", "n", "i0", "i1", "i2", "i3", "i4"])
        #expect(sig.topSessions[0].context == 25)
    }

    /// Context counts in steps of 5 %: a few tokens more is no reason to rewrite the file.
    @Test func contextRoundsToFivePercent() {
        #expect(signature(plan(weekly: 40), [session("w", .working, used: 50_000)])
            == signature(plan(weekly: 40), [session("w", .working, used: 53_000)]))
        #expect(signature(plan(weekly: 40), [session("w", .working, used: 50_000)])
            != signature(plan(weekly: 40), [session("w", .working, used: 60_000)]))
    }

    /// Names, paths, pids and times are not part of it: they don't change what the widgets draw often enough to
    /// be worth a reload on their own (the heartbeat covers them).
    @Test func namesAndTimesAreIgnored() {
        var renamed = session("w", .working)
        renamed.name = "other"
        renamed.activitySince = now.addingTimeInterval(60)
        #expect(signature(plan(weekly: 40), [session("w", .working)]) == signature(plan(weekly: 40), [renamed]))
    }

    @Test func sampleModeAndOptionsCount() {
        #expect(signature(plan(weekly: 40)) != signature(plan(weekly: 40), isSample: true))
        let codex = ToolUsage(tool: .codex, status: .noActivity)
        #expect(signature(plan(weekly: 40)) != signature(plan(weekly: 40), codex: codex))
        #expect(signature(plan(weekly: 40), codex: codex).severities[.codex] == [])
    }
}
