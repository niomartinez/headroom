import Foundation
import Testing
@testable import HeadroomModel

@Suite struct ToolUsageTests {
    private let now = utc("2026-09-24T12:00:00Z")

    @Test func toolNamesAndOrder() {
        #expect(ToolID.allCases == [.claude, .codex, .copilot])
        #expect(ToolID.allCases.map(\.shortName) == ["Claude", "Codex", "Copilot"])
        #expect(ToolID.allCases.map(\.fullName) == ["Claude", "OpenAI Codex", "GitHub Copilot"])
    }

    @Test func staleAfterDefaultsPerTool() {
        #expect(ToolUsage(tool: .codex, status: .noActivity).staleAfter == 30 * minute)
        #expect(ToolUsage(tool: .copilot, status: .notConnected).staleAfter == 45 * minute)
        #expect(ToolUsage(tool: .codex, status: .ok, staleAfter: 10).staleAfter == 10)
    }

    @Test func tightestIsTheHighestKnownPercent() {
        let usage = ToolUsage(
            tool: .codex,
            limits: [
                ToolLimit(window: .weekly, usedPercent: 42, resetsAt: nil, observedAt: now),
                ToolLimit(window: .fiveHour, usedPercent: 55, resetsAt: nil, observedAt: now),
            ],
            status: .ok
        )
        #expect(usage.tightest?.window == .fiveHour)
        #expect(usage.limit(.weekly)?.usedPercent == 42)

        let tie = ToolUsage(
            tool: .codex,
            limits: [
                ToolLimit(window: .weekly, usedPercent: 50, resetsAt: nil, observedAt: now),
                ToolLimit(window: .fiveHour, usedPercent: 50, resetsAt: nil, observedAt: now),
            ],
            status: .ok
        )
        #expect(tie.tightest?.window == .weekly)

        let unknown = ToolUsage(
            tool: .copilot,
            limits: [ToolLimit(window: .monthly, usedPercent: nil, used: 512, resetsAt: nil, observedAt: now)],
            status: .ok
        )
        #expect(unknown.tightest == nil)
    }

    @Test func staleAfterTheNewestObservation() {
        let usage = ToolUsage(
            tool: .codex,
            limits: [
                ToolLimit(window: .weekly, usedPercent: 42, resetsAt: nil, observedAt: now.addingTimeInterval(-hour)),
                ToolLimit(window: .fiveHour, usedPercent: 10, resetsAt: nil, observedAt: now),
            ],
            status: .ok
        )
        #expect(usage.newestObservation == now)
        #expect(!usage.isStale(now: now.addingTimeInterval(30 * minute)))
        #expect(usage.isStale(now: now.addingTimeInterval(30 * minute + 1)))
        #expect(!ToolUsage(tool: .codex, status: .noActivity).isStale(now: now))
    }

    @Test func claudePlanAsToolUsage() {
        let plan = PlanUsage(
            fiveHour: LimitReading(kind: .fiveHour, usedPercent: 14, resetsAt: nil, resetIsEstimated: true,
                                   observedAt: now, source: .desktopApp),
            weekly: LimitReading(kind: .weekly, usedPercent: 89, resetsAt: utc("2026-09-27T11:00:00Z"),
                                 resetIsEstimated: false, observedAt: now, source: .terminal),
            extraUsagePercent: 12
        )
        let usage = ToolUsage(claude: plan)
        #expect(usage.tool == .claude)
        #expect(usage.status == .ok)
        #expect(usage.hasFiveHourWindow)
        #expect(usage.staleAfter == 30 * minute)
        #expect(usage.limits.map(\.window) == [.weekly, .fiveHour])
        #expect(usage.limits.map(\.usedPercent) == [89, 14])
        #expect(usage.limits.map(\.resetIsEstimated) == [false, true])
        #expect(usage.limits[0].resetsAt == utc("2026-09-27T11:00:00Z"))
        #expect(usage.tightest?.window == .weekly)

        let empty = ToolUsage(claude: .empty)
        #expect(empty.limits.isEmpty)
        #expect(empty.status == .noActivity)
        #expect(empty.hasFiveHourWindow)
    }

    @Test func snapshotTracksToolsInDisplayOrder() {
        var snapshot = HeadroomSnapshot.empty(at: now)
        #expect(snapshot.trackedTools == [.claude])
        #expect(snapshot.isClaudeOnly)
        #expect(snapshot.usage(for: .claude)?.tool == .claude)
        #expect(snapshot.usage(for: .codex) == nil)

        snapshot.copilot = ToolUsage(tool: .copilot, status: .notConnected)
        snapshot.codex = ToolUsage(tool: .codex, status: .noActivity)
        #expect(snapshot.trackedTools == [.claude, .codex, .copilot])
        #expect(!snapshot.isClaudeOnly)

        snapshot.claudeTracked = false
        snapshot.codex = nil
        #expect(snapshot.trackedTools == [.copilot])
        #expect(snapshot.usage(for: .claude) == nil)
        #expect(snapshot.usage(for: .copilot)?.status == .notConnected)
    }

    /// Copilot CLI sessions without a usage source (no GitHub sign-in in this build, 1.1 §4.8) still track Copilot.
    @Test func copilotSessionsOnlyIsTracked() {
        var snapshot = HeadroomSnapshot.empty(at: now)
        #expect(!snapshot.isMultiTool)
        snapshot.copilot = .copilotSessionsOnly
        #expect(snapshot.trackedTools == [.claude, .copilot])
        #expect(!snapshot.isClaudeOnly)
        #expect(snapshot.isMultiTool)

        let usage = ToolUsage.copilotSessionsOnly
        #expect(usage.tool == .copilot)
        #expect(usage.status == .sessionsOnly)
        #expect(usage.limits.isEmpty)
        #expect(usage.tightest == nil)
        #expect(!usage.hasFiveHourWindow)
        #expect(!usage.isStale(now: now))

        snapshot.claudeTracked = false
        #expect(snapshot.trackedTools == [.copilot])
        #expect(!snapshot.isMultiTool)
    }

    @Test func toolFromSessionID() {
        #expect(ToolID(sessionID: "5f0c2a4e-1b7d-4c3e-9a01-000000000001") == .claude)
        #expect(ToolID(sessionID: "codex:01a0beba-55ec-7ac1-84a7-16d9f0a456e0") == .codex)
        #expect(ToolID(sessionID: "copilot:7d1e9f00-0000-4000-8000-000000000001") == .copilot)
        #expect(ToolID(sessionID: "") == .claude)
    }

    @Test func sessionsDefaultToClaude() {
        let session = SessionInfo(id: "a", name: "a", projectPath: nil, origin: .desktop, activity: .idle,
                                  activitySince: nil, startedAt: nil, pid: nil, transcriptPath: nil, context: nil)
        #expect(session.tool == .claude)
    }
}
