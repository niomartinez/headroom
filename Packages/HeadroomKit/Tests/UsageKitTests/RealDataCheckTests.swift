import Foundation
import HeadroomModel
import Testing
@testable import UsageKit

/// Read-only check against the developer's real `plan-usage-history.json`. Off unless `HEADROOM_REAL_DATA=1`.
/// Optional ground truth from a terminal status line (epoch seconds): `HEADROOM_TRUTH_5H`, `HEADROOM_TRUTH_7D`.
@Test(.enabled(if: ProcessInfo.processInfo.environment["HEADROOM_REAL_DATA"] != nil))
func realDesktopHistory() throws {
    let env = ProcessInfo.processInfo.environment
    let now = Date()
    let paths = ClaudePaths.standard()
    let samples = try DesktopUsageReader(fileURL: paths.planUsageHistoryFile).readSamples()
    let usage = DesktopUsageAnalyzer.currentUsage(samples: samples, now: now)
    let fiveHour = DesktopUsageAnalyzer.inferFiveHourReset(samples: samples, now: now)
    let weekly = DesktopUsageAnalyzer.inferWeeklyReset(samples: samples, now: now)
    let terminal = TerminalLimitsReader(fileURL: paths.statusLineLatestFile).read()
    let resolved = PlanUsageResolver.resolve(desktop: usage, desktopSamples: samples, terminal: terminal, now: now)

    func describe(_ reading: LimitReading?) -> String {
        guard let reading else { return "none" }
        return "\(reading.usedPercent)% resets \(reading.resetsAt.map { "\($0)" } ?? "nil") observed \(reading.observedAt)"
    }
    func delta(_ inferred: Date?, truthKey: String) -> String {
        guard let inferred, let truth = env[truthKey].flatMap(TimeInterval.init) else { return "" }
        return String(format: " (inferred - truth = %+.0f min)", inferred.timeIntervalSince1970 / 60 - truth / 60)
    }
    print("""
    real data: \(samples.count) samples
      five-hour: \(describe(usage?.fiveHour))
      weekly:    \(describe(usage?.weekly))
      extra:     \(usage?.extraUsagePercent.map { "\($0)%" } ?? "nil")
      inferred five-hour reset after now: \(fiveHour.map { "\($0)" } ?? "nil")\(delta(fiveHour, truthKey: "HEADROOM_TRUTH_5H"))
      inferred weekly reset after now:    \(weekly.map { "\($0)" } ?? "nil")\(delta(weekly, truthKey: "HEADROOM_TRUTH_7D"))
      terminal: \(terminal == nil ? "none" : "five-hour \(describe(terminal?.fiveHour)), weekly \(describe(terminal?.weekly))")
      resolved five-hour: \(describe(resolved.fiveHour))
      resolved weekly:    \(describe(resolved.weekly))
    """)
}
