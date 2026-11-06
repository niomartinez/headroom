import AppKit
import HeadroomModel
import HeadroomSamples
import HeadroomUI
import SwiftUI

/// One PNG: a pill or panel state on a mid-gray canvas so the black pill stands out.
@MainActor
struct RenderScene {
    enum RenderError: Error {
        case renderFailed
        case encodingFailed
    }

    /// The working pulse is frozen part-way through its cycle so the ring is visible.
    static let pulsePhase = 0.35
    static let scale: CGFloat = 2
    static let canvas = Color(.sRGB, white: 0.5, opacity: 1)

    let name: String
    let content: AnyView

    init(_ name: String, _ content: some View) {
        self.name = name
        self.content = AnyView(content)
    }

    func writePNG(to url: URL) throws {
        let renderer = ImageRenderer(content: framed)
        renderer.scale = Self.scale
        guard let image = renderer.cgImage else { throw RenderError.renderFailed }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw RenderError.encodingFailed }
        try png.write(to: url, options: .atomic)
    }

    private var framed: some View {
        content
            .padding(24)
            .background(Self.canvas)
            .environment(\.frozenPulsePhase, Self.pulsePhase)
    }
}

extension RenderScene {
    /// Synthetic data at a fixed date, so the renders come out the same every time.
    static let F = SampleData.fixed

    static var all: [RenderScene] { pills + panels + toolPills + toolPanels + widgets + feedback }

    /// `differentiateWithoutColor` renders as with that accessibility display setting on.
    static func pill(
        _ name: String, _ snapshot: HeadroomSnapshot, moment: Moment? = nil, differentiateWithoutColor: Bool = false,
        tool: ToolID? = nil, gaugePerTool: Bool = false
    ) -> RenderScene {
        RenderScene(
            name,
            PillView(
                snapshot: snapshot, moment: moment, now: F.now, tool: tool, gaugePerTool: gaugePerTool,
                height: PillMetrics.standardHeight
            )
                .environment(\._accessibilityDifferentiateWithoutColor, differentiateWithoutColor)
        )
    }

    static func panel(
        _ name: String, _ snapshot: HeadroomSnapshot, sampleData: PanelSampleData = .hidden, differentiateWithoutColor: Bool = false
    ) -> RenderScene {
        RenderScene(
            name,
            PanelView(snapshot: snapshot, now: F.now, actions: .none, sampleData: sampleData)
                .environment(\._accessibilityDifferentiateWithoutColor, differentiateWithoutColor)
        )
    }

    /// Several panels side by side, top-aligned: one scene for a set of states.
    static func panelSet(_ name: String, _ snapshots: [HeadroomSnapshot], tool: ToolID? = nil, showsCodexOffer: Bool = false) -> RenderScene {
        RenderScene(name, HStack(alignment: .top, spacing: 24) {
            ForEach(Array(snapshots.enumerated()), id: \.offset) { _, snapshot in
                PanelView(snapshot: snapshot, now: F.now, actions: .none, tool: tool, showsCodexOffer: showsCodexOffer)
            }
        })
    }

    /// Several pills stacked, left-aligned.
    static func pillSet(_ name: String, _ items: [(snapshot: HeadroomSnapshot, moment: Moment?, tool: ToolID?, perTool: Bool)]) -> RenderScene {
        RenderScene(name, VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                PillView(
                    snapshot: item.snapshot, moment: item.moment, now: F.now, tool: item.tool, gaugePerTool: item.perTool,
                    height: PillMetrics.standardHeight
                )
            }
        })
    }

    static var pills: [RenderScene] {
        let nearLimit = F.snapshot(F.plan(weekly: 89, fiveHour: 14), F.working)
        return [
            pill("pill-calm", F.snapshot(F.plan(weekly: 31, fiveHour: 8), Array(F.idle.prefix(2)))),
            pill("pill-working", F.snapshot(F.plan(weekly: 42, fiveHour: 23), [F.working[0], F.idle[0]])),
            pill("pill-waiting", F.snapshot(F.plan(weekly: 42, fiveHour: 23), [F.working[0], F.waitingTerminal])),
            pill("pill-near-limit", nearLimit),
            pill("pill-critical", F.snapshot(F.plan(weekly: 97, fiveHour: 62), [F.working[0]])),
            pill("pill-stale", F.snapshot(F.plan(weekly: 89, fiveHour: 14, age: 45 * 60), F.working)),
            pill("pill-nodata", F.snapshot(.empty, [], connected: false)),
            pill("pill-moment-finished", nearLimit, moment: .sessionFinished(sessionID: "i2", name: "Update pricing table")),
            pill("pill-moment-input", nearLimit, moment: .sessionNeedsInput(sessionID: "t1", name: "harbor")),
            pill("pill-moment-limit", F.snapshot(F.plan(weekly: 90, fiveHour: 14), F.working), moment: .limitCrossed(kind: .weekly, percent: 90)),
            pill("pill-stale-critical", F.snapshot(F.plan(weekly: 97, fiveHour: 62, age: 45 * 60), [F.working[0]])),
            // Differentiate Without Color: the waiting dot is a ring, the working dot stays a disc.
            pill("pill-waiting-no-color", F.snapshot(F.plan(weekly: 42, fiveHour: 23), [F.working[0], F.waitingTerminal]),
                 differentiateWithoutColor: true),
            pill("pill-working-no-color", F.snapshot(F.plan(weekly: 42, fiveHour: 23), [F.working[0], F.idle[0]]),
                 differentiateWithoutColor: true),
        ] + wideMomentPills
    }

    /// Wide glyphs: the pill stays capped and only the name is cut.
    static var wideMomentPills: [RenderScene] {
        let nearLimit = F.snapshot(F.plan(weekly: 89, fiveHour: 14), F.working)
        return SampleData.wideNames.sorted { $0.key < $1.key }.flatMap { key, name in
            [
                pill("pill-moment-wide-\(key)-finished", nearLimit, moment: .sessionFinished(sessionID: "x", name: name)),
                pill("pill-moment-wide-\(key)-input", nearLimit, moment: .sessionNeedsInput(sessionID: "x", name: name)),
            ]
        }
    }

    static var panels: [RenderScene] {
        [
            panel("panel-full", F.full),
            panel("panel-empty", F.snapshot(F.plan(weekly: 89, fiveHour: 14), [])),
            panel("panel-no-access", F.snapshot(.empty, [], issues: [.claudeCodeFolderUnavailable, .desktopFolderUnavailable], connected: false)),
            panel("panel-stale", F.snapshot(
                F.plan(weekly: 89, fiveHour: 14, age: 42 * 60, estimated: true, extra: 12),
                [F.working[0], F.idle[0], F.longName]
            )),
            panel("panel-crowded-rows", F.snapshot(F.plan(weekly: 42, fiveHour: 23), F.crowdedRows)),
            panel("panel-assumed-window", F.snapshot(F.plan(weekly: 42, fiveHour: 23), F.assumedWindows)),
            panel("panel-no-color", F.snapshot(F.plan(weekly: 42, fiveHour: 23), [F.working[0], F.waitingTerminal, F.idle[0]]),
                  differentiateWithoutColor: true),
            // Sample data mode: the offer on a Mac without Claude data, and the showcase it shows.
            panel("panel-sample-offer", F.snapshot(.empty, [], connected: false), sampleData: .offered),
            panel("panel-sample-showing", F.claudeOnlyShowcase(terminalConnected: false), sampleData: .showing),
        ]
    }

    // MARK: Codex and Copilot (1.1 §11.3)

    static var toolPills: [RenderScene] {
        let multi = F.multiTool
        var codexStale = multi
        codexStale.codex = F.codex(weekly: 94, age: 3 * 3600)
        var allWarnings = F.snapshot(F.plan(weekly: 94, fiveHour: 10), F.working)
        allWarnings.codex = F.codex(weekly: 85)
        allWarnings.copilot = F.copilot(used: 1_500)
        return [
            pill("pill-every-tool-warning", allWarnings, gaugePerTool: true),
            // Weekly only: one ring and no inner track, so it can't read as "5-hour 0 %"; then past 75 %.
            pillSet("pill-codex-weekly-only", [
                (F.withoutClaude(codex: F.codex(weekly: 42, fiveHour: nil), [F.codexSession]), nil, nil, false),
                (F.withoutClaude(codex: F.codex(weekly: 94, fiveHour: nil), [F.codexSession]), nil, nil, false),
            ]),
            // A plan picked (34 %), "Not sure" (tracks only), and near the allowance.
            pillSet("pill-copilot", [
                (F.withoutClaude(copilot: F.copilot()), nil, nil, false),
                (F.withoutClaude(copilot: F.copilot(allowance: nil)), nil, nil, false),
                (F.withoutClaude(copilot: F.copilot(used: 1_380), [F.copilotSession]), nil, nil, false),
            ]),
            // Automatic shows Claude; Rings show Codex; one gauge per tool with its own warning percentage; and
            // with Codex stale, only its gauge dims.
            pillSet("pill-gauge-per-tool", [
                (multi, nil, nil, false),
                (multi, nil, .codex, false),
                (multi, nil, nil, true),
                (codexStale, nil, nil, true),
                (multi, .sessionNeedsInput(sessionID: F.copilotSession.id, name: "billing"), nil, true),
            ]),
            // Limit moments name their tool with two or more tools; Copilot's 100 % is "used up".
            pillSet("pill-moment-codex-limit", [
                (multi, .toolLimitCrossed(tool: .codex, window: .weekly, percent: 90), nil, false),
                (multi, .limitCrossed(kind: .fiveHour, percent: 90), nil, false),
                (multi, .toolLimitCrossed(tool: .copilot, window: .monthly, percent: 100), nil, false),
                (F.withoutClaude(codex: F.codex(weekly: 100)), .toolLimitCrossed(tool: .codex, window: .weekly, percent: 100), nil, false),
                (F.withoutClaude(copilot: F.copilot(used: 1_500)), .toolLimitCrossed(tool: .copilot, window: .monthly, percent: 100), nil, false),
            ]),
        ]
    }

    static var toolPanels: [RenderScene] {
        let multi = F.multiTool
        func claudeAnd(codex: ToolUsage? = nil, copilot: ToolUsage? = nil, _ sessions: [SessionInfo]) -> HeadroomSnapshot {
            var snapshot = F.snapshot(F.plan(weekly: 42, fiveHour: 23), sessions)
            snapshot.codex = codex
            snapshot.copilot = copilot
            return snapshot
        }
        var pastReset = F.codex(weekly: 0, fiveHour: nil, age: 26 * 3600)
        pastReset.limits[0].resetsAt = nil
        pastReset.limits[0].resetSinceReading = true
        return [
            panelSet("panel-multi-tool", [multi]),
            panelSet("panel-multi-tool-codex-sessions", [
                claudeAnd(codex: F.codex(), copilot: F.copilot(), [F.codexSession, F.codexTerminalSession]),
            ]),
            // The header follows Rings show.
            panelSet("panel-multi-tool-rings-codex", [multi], tool: .codex),
            // Plus (two windows, a Spark bucket past 75 %) and Pro (one window, centred by the gauge).
            panelSet("panel-codex-only", [
                F.withoutClaude(codex: F.codex(otherBuckets: [F.codexSparkBucket()]), [F.codexSession, F.codexTerminalSession]),
                F.withoutClaude(codex: F.codex(weekly: 42, fiveHour: nil), [F.codexSession]),
                F.withoutClaude(codex: F.codex(status: .noActivity), []),
            ]),
            // Compact Codex rows: no reading, stale, past its reset, another bucket past 75 %.
            panelSet("panel-codex-states", [
                claudeAnd(codex: F.codex(status: .noActivity), [F.working[0]]),
                claudeAnd(codex: F.codex(age: 3 * 3600), [F.working[0]]),
                claudeAnd(codex: pastReset, [F.working[0]]),
                claudeAnd(codex: F.codex(weekly: 42, fiveHour: nil, otherBuckets: [F.codexSparkBucket()]), [F.working[0]]),
            ]),
            // Compact Copilot rows (§4.6): not connected, no individual usage, sign-in expired, offline (the
            // last reading, dimmed), no plan picked, extra usage billed, and an organization seat (§4.1).
            panelSet("panel-copilot-states", [
                claudeAnd(copilot: F.copilot(status: .notConnected), [F.working[0]]),
                claudeAnd(copilot: F.copilot(status: .noIndividualUsage), [F.working[0]]),
                claudeAnd(copilot: F.copilot(status: .signInExpired), [F.working[0]]),
                claudeAnd(copilot: F.copilot(status: .offline, age: 2 * 3600), [F.working[0]]),
                claudeAnd(copilot: F.copilot(allowance: nil), [F.working[0]]),
                claudeAnd(copilot: F.copilot(used: 1_620, extra: 120), [F.working[0]]),
                claudeAnd(copilot: F.copilot(used: 1_348, allowance: 50_000, planName: "Enterprise"), [F.working[0]]),
            ]),
            // Copilot alone: the header with its amount line, without a plan, and not connected.
            panelSet("panel-copilot-only", [
                F.withoutClaude(copilot: F.copilot(), [F.copilotSession]),
                F.withoutClaude(copilot: F.copilot(allowance: nil, extra: 120)),
                F.withoutClaude(copilot: F.copilot(status: .notConnected)),
                F.withoutClaude(copilot: F.copilot(status: .signInExpired)),
            ]),
            panelSet("panel-codex-offer", [F.snapshot(F.plan(weekly: 42, fiveHour: 23), [F.working[0], F.idle[0]])], showsCodexOffer: true),
            // Tool tags appear only when the list mixes tools.
            panelSet("panel-mixed-sessions", [
                claudeAnd(codex: F.codex(), F.working + [F.codexSession, F.waitingTerminal, F.codexTerminalSession, F.idle[0]]),
                F.withoutClaude(codex: F.codex(), [F.codexSession, F.codexTerminalSession]),
            ]),
            // Access: only Codex's folder missing, then Claude's and Codex's.
            panelSet("panel-access-codex", [
                claudeAnd(codex: F.codex(status: .needsAccess), [F.working[0]]).adding(issues: [.codexFolderUnavailable]),
                F.snapshot(.empty, [], issues: [.claudeCodeFolderUnavailable, .desktopFolderUnavailable, .codexFolderUnavailable],
                           connected: false).tracking(codex: F.codex(status: .needsAccess)),
            ]),
            // Empty lists: Codex only, and two tools.
            panelSet("panel-tools-empty", [
                F.withoutClaude(codex: F.codex(weekly: 42, fiveHour: nil)),
                claudeAnd(codex: F.codex(weekly: 42, fiveHour: nil), []),
            ]),
            // Sample data mode shows all three tools (1.1 §6.5).
            RenderScene("panel-sample-showing-tools", PanelView(
                snapshot: F.showcase(terminalConnected: false), now: F.now, actions: .none, sampleData: .showing
            )),
        ]
    }
}

private extension HeadroomSnapshot {
    func adding(issues more: Set<DataIssue>) -> HeadroomSnapshot {
        var snapshot = self
        snapshot.issues.formUnion(more)
        return snapshot
    }

    func tracking(codex: ToolUsage) -> HeadroomSnapshot {
        var snapshot = self
        snapshot.codex = codex
        return snapshot
    }
}
