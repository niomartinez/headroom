import Foundation
import Testing
@testable import HeadroomModel

@Test func severityThresholds() {
    #expect(Thresholds.limits.severity(for: 74.9) == .normal)
    #expect(Thresholds.limits.severity(for: 75) == .warning)
    #expect(Thresholds.limits.severity(for: 95) == .critical)
    #expect(Thresholds.context.severity(for: 90) == .critical)
}

@Test func contextPercentClamps() {
    let c = ContextUsage(usedTokens: 1_500_000, windowTokens: 1_000_000, model: nil, windowIsExact: false, observedAt: nil)
    #expect(c.percent == 100)
    #expect(ContextUsage(usedTokens: 50, windowTokens: 0, model: nil, windowIsExact: false, observedAt: nil).percent == 0)
}

@Test func contextWindowIsNotAssumedByDefault() {
    let known = ContextUsage(usedTokens: 10, windowTokens: 200_000, model: nil, windowIsExact: false, observedAt: nil)
    #expect(!known.windowIsAssumed)
    let assumed = ContextUsage(
        usedTokens: 10, windowTokens: 200_000, model: nil, windowIsExact: false, observedAt: nil, windowIsAssumed: true
    )
    #expect(assumed.windowIsAssumed)
    #expect(assumed != known)
}

@Test func contextUsageRoundTripsWindowIsAssumed() throws {
    let assumed = ContextUsage(
        usedTokens: 168_000, windowTokens: 200_000, model: "claude-x", windowIsExact: false,
        observedAt: Date(timeIntervalSince1970: 1_790_000_000), windowIsAssumed: true
    )
    let data = try JSONEncoder().encode(assumed)
    #expect(try JSONDecoder().decode(ContextUsage.self, from: data) == assumed)
}

/// JSON written before `windowIsAssumed` existed still decodes, as a window that is not assumed.
@Test func olderContextUsageJSONDecodes() throws {
    let json = #"{"usedTokens":52400,"windowTokens":200000,"model":"claude-haiku-4-5","windowIsExact":true}"#
    let decoded = try JSONDecoder().decode(ContextUsage.self, from: Data(json.utf8))
    #expect(decoded == ContextUsage(
        usedTokens: 52_400, windowTokens: 200_000, model: "claude-haiku-4-5", windowIsExact: true, observedAt: nil
    ))
    #expect(!decoded.windowIsAssumed)
}

@Test func projectNameHidesScratchAndDuplicates() {
    func s(_ path: String?, name: String = "Fix bug") -> SessionInfo {
        SessionInfo(id: "a", name: name, projectPath: path, origin: .desktop, activity: .idle,
                    activitySince: nil, startedAt: nil, pid: nil, transcriptPath: nil, context: nil)
    }
    #expect(s("/Users/me/code/app").projectName == "app")
    #expect(s("/Users/me/Library/Application Support/Claude/scratch-workspaces/x/y/scratch-1").projectName == nil)
    #expect(s("/Users/me/code/app", name: "app").projectName == nil)
    #expect(s(nil).projectName == nil)
}

@Test func sortOrderWorkingWaitingIdleThenRecent() {
    func s(_ id: String, _ a: SessionActivity, _ t: TimeInterval) -> SessionInfo {
        SessionInfo(id: id, name: id, projectPath: nil, origin: .desktop, activity: a,
                    activitySince: Date(timeIntervalSince1970: t), startedAt: nil, pid: nil, transcriptPath: nil, context: nil)
    }
    let sorted = [s("i1", .idle, 5), s("w1", .working, 1), s("q", .waitingForInput, 9), s("i2", .idle, 7), s("w2", .working, 3)].sortedForDisplay()
    #expect(sorted.map(\.id) == ["w2", "w1", "q", "i2", "i1"])
}

@Test func tightestLimit() {
    let now = Date()
    let p = PlanUsage(
        fiveHour: LimitReading(kind: .fiveHour, usedPercent: 14, resetsAt: nil, resetIsEstimated: true, observedAt: now, source: .desktopApp),
        weekly: LimitReading(kind: .weekly, usedPercent: 89, resetsAt: nil, resetIsEstimated: true, observedAt: now, source: .desktopApp))
    #expect(p.tightest?.kind == .weekly)
    #expect(p.weekly?.isStale(now: now.addingTimeInterval(31 * 60)) == true)
}

@Test func standardPathsUseRealHome() {
    let p = ClaudePaths.standard(home: URL(fileURLWithPath: "/Users/me"))
    #expect(p.planUsageHistoryFile.path == "/Users/me/Library/Application Support/Claude/plan-usage-history.json")
    #expect(p.statusLineLatestFile.path == "/Users/me/.claude/headroom/statusline-latest.json")
}
