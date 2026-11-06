import HeadroomModel
import HeadroomSamples
import HeadroomUI
import SwiftUI

// Nio's feedback (1.1 §14): the ring key, the needs-you rest state and row marks, click-to-open hovers and the
// taller pill. Synthetic names only. Hover states are drawn through the preview environment values, since
// ImageRenderer can't hover.

extension RenderScene {
    static var feedback: [RenderScene] {
        ringKeyPanels + needsYouPills + needsYouPanels + justFinishedPanels + openHoverPanels + tallPills
    }

    /// A second session waiting, for "2 need you" and the dismissed row.
    static var waitingDesktop: SessionInfo {
        F.session("n2", .waitingForInput, name: "Review pricing copy", project: "/Users/me/code/website", used: 96_000,
                  minutesAgo: 6)
    }

    // MARK: Ring key (§14.2)

    static func ringKeyPanel(_ name: String, _ plan: PlanUsage, hovered: GaugeRing? = nil) -> RenderScene {
        RenderScene(
            name,
            PanelView(snapshot: F.snapshot(plan, [F.working[0], F.idle[0]]), now: F.now, actions: .none)
                .environment(\.previewHoveredLimitRing, hovered)
        )
    }

    static var ringKeyPanels: [RenderScene] {
        [
            ringKeyPanel("panel-ring-key-normal", F.plan(weekly: 42, fiveHour: 23)),
            ringKeyPanel("panel-ring-key-warning", F.plan(weekly: 88, fiveHour: 23)),
            ringKeyPanel("panel-ring-key-critical", F.plan(weekly: 97, fiveHour: 96)),
            ringKeyPanel("panel-ring-key-stale", F.plan(weekly: 88, fiveHour: 14, age: 45 * 60)),
            ringKeyPanel("panel-ring-key-hover-weekly", F.plan(weekly: 61, fiveHour: 54), hovered: .outer),
            ringKeyPanel("panel-ring-key-hover-5hour", F.plan(weekly: 61, fiveHour: 54), hovered: .inner),
        ]
    }

    // MARK: Needs you (§14.4)

    static func restPill(
        _ name: String, _ plan: PlanUsage, waiting: [SessionInfo], attention: [String], height: CGFloat = PillMetrics.standardHeight
    ) -> RenderScene {
        RenderScene(
            name,
            PillView(
                snapshot: F.snapshot(plan, [F.working[0]] + waiting), moment: nil, now: F.now,
                attention: NeedsYouAttention(names: attention), height: height
            )
        )
    }

    static var needsYouPills: [RenderScene] {
        let nearLimit = F.plan(weekly: 89, fiveHour: 14)
        let wide = SampleData.wideNames.sorted { $0.key < $1.key }.map { key, name in
            restPill(
                "pill-needs-you-long-\(key)", nearLimit,
                waiting: [F.session("x", .waitingForInput, name: name, project: nil)], attention: [name]
            )
        }
        return [
            restPill("pill-needs-you-one", nearLimit, waiting: [F.waitingTerminal], attention: ["harbor"]),
            // Below 75 %: no number, so the rest state is narrower.
            restPill("pill-needs-you-calm", F.plan(weekly: 42, fiveHour: 23), waiting: [F.waitingTerminal], attention: ["harbor"]),
            restPill(
                "pill-needs-you-two", nearLimit, waiting: [F.waitingTerminal, waitingDesktop],
                attention: ["harbor", "Review pricing copy"]
            ),
            restPill(
                "pill-needs-you-long", nearLimit, waiting: [waitingDesktop], attention: ["Review pricing copy for the launch"]
            ),
        ] + wide
    }

    static var needsYouPanels: [RenderScene] {
        let plan = F.plan(weekly: 89, fiveHour: 14)
        let sessions = F.working + [F.waitingTerminal, waitingDesktop] + Array(F.idle.prefix(2))
        // The app shows dismissed waits as idle; the panel lists them last in Needs you.
        let dismissed = F.snapshot(plan, sessions).applyingDismissals([F.waitingTerminal.id])
        let open = PanelActions(sessionOpenTitle: { id in id == F.waitingTerminal.id ? "Show in Terminal" : "Open in Claude" })
        return [
            RenderScene("panel-needs-you-unseen", PanelView(
                snapshot: F.snapshot(plan, sessions), now: F.now, actions: .none, unseenIDs: [F.waitingTerminal.id, waitingDesktop.id]
            )),
            RenderScene("panel-needs-you-dismissed", PanelView(
                snapshot: dismissed, now: F.now, actions: .none, dismissedIDs: [F.waitingTerminal.id]
            )),
            RenderScene(
                "panel-needs-you-hover-dismiss",
                PanelView(snapshot: F.snapshot(plan, sessions), now: F.now, actions: open)
                    .environment(\.previewHoveredSessionID, waitingDesktop.id)
            ),
        ]
    }

    // MARK: Just finished (1.1.1)

    static var justFinishedPanels: [RenderScene] {
        let plan = F.plan(weekly: 61, fiveHour: 34)
        let sessions = F.working + [waitingDesktop] + F.idle
        let finished: Set<String> = [F.idle[0].id, F.idle[1].id]
        let open = PanelActions(sessionOpenTitle: { _ in "Open in Claude" })
        return [
            RenderScene("panel-just-finished", PanelView(
                snapshot: F.snapshot(plan, sessions), now: F.now, actions: .none, finishedIDs: finished
            )),
            RenderScene(
                "panel-just-finished-hover",
                PanelView(snapshot: F.snapshot(plan, sessions), now: F.now, actions: open, finishedIDs: finished)
                    .environment(\.previewHoveredSessionID, F.idle[0].id)
            ),
        ]
    }

    // MARK: Click to open (§14.3)

    static func openHover(_ name: String, _ snapshot: HeadroomSnapshot, hovered: String, terminalApp: String = "Terminal") -> RenderScene {
        let origins = Dictionary(uniqueKeysWithValues: snapshot.sessions.map { ($0.id, $0.origin) })
        let actions = PanelActions(sessionOpenTitle: { id in
            origins[id] == .terminal ? "Show in \(terminalApp)" : "Open in Claude"
        })
        return RenderScene(
            name,
            PanelView(snapshot: snapshot, now: F.now, actions: actions).environment(\.previewHoveredSessionID, hovered)
        )
    }

    static var openHoverPanels: [RenderScene] {
        let plan = F.plan(weekly: 89, fiveHour: 14)
        let sessions = F.working + [F.idle[0], F.idle[1]]
        let terminal = F.session("t2", .idle, name: "atlas", project: "/Users/me/code/atlas", origin: .terminal, used: 64_000,
                                 window: 200_000, minutesAgo: 20)
        return [
            openHover("panel-open-hover-desktop", F.snapshot(plan, sessions), hovered: F.working[0].id),
            openHover("panel-open-hover-terminal", F.snapshot(plan, sessions + [terminal]), hovered: terminal.id),
            openHover("panel-open-hover-vscode", F.snapshot(plan, sessions + [terminal]), hovered: terminal.id, terminalApp: "VS Code"),
            openHover("panel-open-hover-long-name", F.snapshot(plan, [F.working[0], F.longName]), hovered: F.longName.id),
        ]
    }

    // MARK: Taller pill (§14.6)

    /// The same pills at 1.0's 22 pt, the standard 24 pt and a 30 pt pill (a 36 pt menu bar).
    static var tallPills: [RenderScene] {
        let nearLimit = F.snapshot(F.plan(weekly: 89, fiveHour: 14), F.working + [F.waitingTerminal])
        return [22.0, 24, 30].map { height in
            RenderScene("pill-height-\(Int(height))", VStack(alignment: .leading, spacing: 12) {
                PillView(snapshot: nearLimit, moment: nil, now: F.now, height: height)
                PillView(snapshot: nearLimit, moment: .sessionNeedsInput(sessionID: "t1", name: "harbor"), now: F.now, height: height)
                PillView(snapshot: nearLimit, moment: nil, now: F.now, attention: NeedsYouAttention(names: ["harbor"]), height: height)
                PillView(snapshot: F.snapshot(F.plan(weekly: 97, fiveHour: 96), [F.working[0]]), moment: nil, now: F.now, height: height)
            })
        }
    }
}
