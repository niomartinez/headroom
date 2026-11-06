import AppKit
import HeadroomModel
import HeadroomUI
import SwiftUI

// The website's hero panel and social-card pill, from synthetic data on a transparent background.
// Usage: swift run hero-render <output-directory>   (see website/README.md)
//
// Synthetic data only: made-up names and paths (copied from headroom-render's fixtures).
let calendar = Calendar.autoupdatingCurrent
func localDate(day: Int, hour: Int, minute: Int) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}
let now = localDate(day: 24, hour: 14, minute: 10)
let weeklyReset = localDate(day: 27, hour: 19, minute: 0)
let fiveHourReset = now.addingTimeInterval(2 * 3600 + 50 * 60)

func plan(weekly: Double, fiveHour: Double, age: TimeInterval = 120) -> PlanUsage {
    let observedAt = now.addingTimeInterval(-age)
    return PlanUsage(
        fiveHour: LimitReading(kind: .fiveHour, usedPercent: fiveHour, resetsAt: fiveHourReset, resetIsEstimated: false, observedAt: observedAt, source: .desktopApp),
        weekly: LimitReading(kind: .weekly, usedPercent: weekly, resetsAt: weeklyReset, resetIsEstimated: false, observedAt: observedAt, source: .desktopApp)
    )
}

func session(_ id: String, _ activity: SessionActivity, name: String, project: String?, origin: SessionOrigin = .desktop,
             used: Int? = nil, window: Int = 1_000_000, model: String = "claude-opus-5-5", minutesAgo: Double = 1) -> SessionInfo {
    SessionInfo(
        id: id, name: name, projectPath: project, origin: origin, activity: activity,
        activitySince: now.addingTimeInterval(-minutesAgo * 60), startedAt: now.addingTimeInterval(-3 * 3600),
        pid: nil, transcriptPath: nil,
        context: used.map { ContextUsage(usedTokens: $0, windowTokens: window, model: model, windowIsExact: false, observedAt: nil) }
    )
}

let working = [
    session("w1", .working, name: "Refactor invoice export", project: "/Users/me/code/ledger", used: 720_000),
    session("w2", .working, name: "Draft onboarding emails", project: "/Users/me/code/website", used: 28_000, window: 200_000, model: "claude-haiku-4-5", minutesAgo: 3),
]
let idle = [
    session("i1", .idle, name: "Fix flaky upload test", project: "/Users/me/code/atlas", used: 850_000, minutesAgo: 4),
    session("i2", .idle, name: "Update pricing table", project: "/Users/me/code/website", used: 142_000, window: 200_000, minutesAgo: 9),
    session("i3", .idle, name: "Tidy CI workflow", project: "/Users/me/code/atlas", used: 290_000, minutesAgo: 15),
    session("i4", .idle, name: "Write release notes", project: "/Users/me/code/ledger", used: 120_000, minutesAgo: 40),
    session("i5", .idle, name: "Rename settings keys", project: "/Users/me/code/harbor", used: 16_000, window: 200_000, minutesAgo: 95),
]

let hero = HeadroomSnapshot(plan: plan(weekly: 89, fiveHour: 14), sessions: working + idle, terminalBridgeConnected: true, issues: [], generatedAt: now)
let pillSnapshot = HeadroomSnapshot(plan: plan(weekly: 89, fiveHour: 14), sessions: working, terminalBridgeConnected: true, issues: [], generatedAt: now)

@MainActor
func write(_ view: some View, scale: CGFloat, phase: Double, to url: URL) throws {
    let renderer = ImageRenderer(content: view.environment(\.frozenPulsePhase, phase))
    renderer.scale = scale
    renderer.isOpaque = false
    guard let image = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "hero-render", code: 1)
    }
    try png.write(to: url, options: .atomic)
    print(url.path, image.width, image.height)
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: hero-render <output-directory>\n".utf8))
    exit(64)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try MainActor.assumeIsolated {
    // Phase 1: the ring is fully faded, so the page can draw a live pulse on top.
    try write(PanelView(snapshot: hero, now: now, actions: .none), scale: 3, phase: 1, to: out.appendingPathComponent("hero-panel@3x.png"))
    try write(PillView(snapshot: pillSnapshot, moment: nil, now: now), scale: 6, phase: 0.35, to: out.appendingPathComponent("pill@6x.png"))
}
