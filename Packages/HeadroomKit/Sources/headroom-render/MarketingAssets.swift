import HeadroomModel
import HeadroomSamples
import HeadroomUI
import SwiftUI

/// Website-ready PNGs with transparent backgrounds (`headroom-render --assets <dir>`): pill states at
/// 3×, panels at 2×. Synthetic data only (`SampleData.fixed`).
@MainActor
struct MarketingAsset {
    let name: String
    let scale: CGFloat
    let content: AnyView

    init(_ name: String, scale: CGFloat, _ content: some View) {
        self.name = name
        self.scale = scale
        self.content = AnyView(
            content
                .environment(\.frozenPulsePhase, RenderScene.pulsePhase)
                .environment(\.colorScheme, .dark)
        )
    }

    func write(to url: URL) throws {
        try ImageExport.writeTransparent(content, scale: scale, to: url)
    }
}

extension MarketingAsset {
    static let S = SampleData.fixed

    static var all: [MarketingAsset] { pills + toolPills + panels }

    static func pill(_ name: String, _ snapshot: HeadroomSnapshot, moment: Moment? = nil) -> MarketingAsset {
        MarketingAsset("pill-\(name)@3x", scale: 3, PillView(snapshot: snapshot, moment: moment, now: S.now, height: PillMetrics.standardHeight))
    }

    static func panel(_ name: String, _ snapshot: HeadroomSnapshot) -> MarketingAsset {
        MarketingAsset("panel-\(name)@2x", scale: 2, PanelView(snapshot: snapshot, now: S.now, actions: .none))
    }

    static var pills: [MarketingAsset] {
        let nearLimit = S.snapshot(S.plan(weekly: 89, fiveHour: 14), S.working)
        return [
            pill("calm", S.snapshot(S.plan(weekly: 31, fiveHour: 8), Array(S.idle.prefix(2)))),
            pill("working", S.snapshot(S.plan(weekly: 42, fiveHour: 23), [S.working[0], S.idle[0]])),
            pill("working-two", S.snapshot(S.plan(weekly: 58, fiveHour: 41), S.working)),
            pill("waiting", S.snapshot(S.plan(weekly: 42, fiveHour: 23), [S.working[0], S.waitingTerminal])),
            pill("near-limit", nearLimit),
            pill("critical", S.snapshot(S.plan(weekly: 97, fiveHour: 62), [S.working[0]])),
            pill("moment-finished", nearLimit, moment: .sessionFinished(sessionID: "i2", name: "Update pricing table")),
            pill("moment-input", nearLimit, moment: .sessionNeedsInput(sessionID: "t1", name: "harbor")),
            pill("moment-limit", S.snapshot(S.plan(weekly: 90, fiveHour: 14), S.working), moment: .limitCrossed(kind: .weekly, percent: 90)),
        ]
    }

    /// The 1.1 pill states (spec §6.1, §14.4): "needs you" resting in the pill, other tools' rings, one gauge
    /// per tool, and a limit moment that names its tool.
    static var toolPills: [MarketingAsset] {
        let height = PillMetrics.standardHeight
        let nearLimit = S.snapshot(S.plan(weekly: 89, fiveHour: 14), [S.working[0], S.waitingTerminal])
        let multi = S.multiTool
        func toolPill(_ name: String, _ view: PillView) -> MarketingAsset {
            MarketingAsset("pill-\(name)@3x", scale: 3, view)
        }
        return [
            toolPill("needs-you", PillView(
                snapshot: nearLimit, moment: nil, now: S.now, attention: NeedsYouAttention(names: ["harbor"]), height: height
            )),
            toolPill("needs-you-two", PillView(
                snapshot: nearLimit, moment: nil, now: S.now,
                attention: NeedsYouAttention(names: ["harbor", "Review pricing copy"]), height: height
            )),
            toolPill("codex-weekly", PillView(
                snapshot: S.withoutClaude(codex: S.codex(weekly: 94, fiveHour: nil), [S.codexSession]), moment: nil, now: S.now,
                height: height
            )),
            toolPill("copilot", PillView(snapshot: S.withoutClaude(copilot: S.copilot()), moment: nil, now: S.now, height: height)),
            toolPill("gauge-per-tool", PillView(snapshot: multi, moment: nil, now: S.now, gaugePerTool: true, height: height)),
            toolPill("moment-codex-limit", PillView(
                snapshot: multi, moment: .toolLimitCrossed(tool: .codex, window: .weekly, percent: 90), now: S.now, height: height
            )),
        ]
    }

    static var panels: [MarketingAsset] {
        [
            panel("overview", S.snapshot(
                S.plan(weekly: 58, fiveHour: 41),
                S.working + [S.waitingTerminal] + Array(S.idle.prefix(4))
            )),
            panel("near-limit", S.snapshot(S.plan(weekly: 91, fiveHour: 97), [S.working[0], S.waitingTerminal] + Array(S.idle.prefix(2)))),
            panel("calm", S.snapshot(S.plan(weekly: 31, fiveHour: 12), [S.working[1]] + Array(S.idle.prefix(3)))),
        ]
    }
}

// MARK: - Feature snippets (1.1 §10)

extension MarketingAsset {
    /// The 1.1 feature snippets (`headroom-render --marketing <dir>`), 2× on transparent backgrounds: Codex (a
    /// panel with the Codex row and Codex sessions), Copilot (its row and the Settings account row) and widgets (the
    /// desktop grid of store screenshot 07), plus the compact session icons and footer legend, and 1.1.1's Just
    /// finished section with the footer's Refresh button.
    static var snippets: [MarketingAsset] {
        var codex = S.snapshot(S.plan(weekly: 58, fiveHour: 41), [S.working[0], S.codexSession, S.idle[1], S.codexTerminalSession])
        codex.codex = S.codex()
        var copilot = S.snapshot(S.plan(weekly: 58, fiveHour: 41), [S.working[0], S.copilotSession])
        copilot.copilot = S.copilot()
        var sessionTools = S.snapshot(S.plan(weekly: 40, fiveHour: 18), [
            S.session("claude-test", .working, name: "Refine session badges", project: "/Users/me/headroom", used: 180_000),
            S.session("codex:test", .working, name: "Smooth pill completion", project: "/Users/me/headroom", used: 65_000, tool: .codex),
            S.session("copilot:test", .working, name: "Check release build", project: "/Users/me/website", used: 120_000, tool: .copilot),
            S.session("codex:waiting", .waitingForInput, name: "Review motion", project: "/Users/me/headroom", used: 32_000, tool: .codex),
        ])
        sessionTools.codex = ToolUsage(tool: .codex, status: .sessionsOnly)
        sessionTools.copilot = .copilotSessionsOnly
        let justFinished = S.snapshot(S.plan(weekly: 52, fiveHour: 27), [S.working[0]] + Array(S.idle.prefix(4)))
        return [
            MarketingAsset("snippet-session-tools@2x", scale: 2, PanelView(
                snapshot: sessionTools, now: S.now, actions: .none, unseenIDs: ["codex:waiting"]
            ).environment(\.frozenPulsePhase, 1)),
            MarketingAsset("snippet-codex@2x", scale: 2, PanelView(snapshot: codex, now: S.now, actions: .none)),
            MarketingAsset("snippet-copilot@2x", scale: 2, HStack(alignment: .top, spacing: 24) {
                PanelView(snapshot: copilot, now: S.now, actions: .none)
                GitHubAccountCard()
            }),
            MarketingAsset("snippet-widgets@2x", scale: 2, WidgetDesktopGrid(file: WidgetSamples.file(WidgetSamples.multiTool))),
            MarketingAsset("snippet-just-finished@2x", scale: 2, PanelView(
                snapshot: justFinished, now: S.now, actions: .none, finishedIDs: [S.idle[0].id, S.idle[1].id]
            ).environment(\.frozenPulsePhase, 1)),
        ]
    }
}

/// Settings › Tools › GitHub Copilot's account row, drawn (ImageRenderer can't draw AppKit controls), with the
/// copy of 1.1 §4.6 and §6.4 for a made-up account.
struct GitHubAccountCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GitHub Copilot")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GitHub account")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.92))
                        Text("Connected as @octocat · updated 5m ago")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    Spacer(minLength: 8)
                    Text("Disconnect")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.14)))
                }
                HStack {
                    Text("Plan")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.92))
                    Spacer(minLength: 8)
                    Text("Pro · 1,500 credits a month")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                Text("Copilot's usage is kept on GitHub, not on your Mac. Headroom asks GitHub for this month's usage every 15 minutes with read-only billing access, using its own sign-in.")
                    .font(.system(size: 11))
                    .lineSpacing(2)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
            )
        }
        .padding(14)
        .frame(width: 372)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x232325)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}
