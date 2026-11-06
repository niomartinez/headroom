import AppKit
import HeadroomModel
import HeadroomSamples
import HeadroomShare
import HeadroomUI
import HeadroomWidgetUI
import SwiftUI
import WidgetKit

// Widget renders (1.1 §11.3) and store screenshot 07. Synthetic data only: SampleData.fixed plus the made-up Codex
// and Copilot values of §6.5.
//
// Widget sizes are assumptions, not WidgetKit's: the extension logs `context.displaySize` once per family on a
// real desktop, and these should be checked against it. Small 170×170, medium 364×170, large 364×382 pt, with
// 16 pt content margins and a 22 pt corner radius.

/// A widget's outline on the review canvas or a store desktop.
enum WidgetFrameSize {
    case small
    case medium
    case large

    var points: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        }
    }

    static let contentMargin: CGFloat = 16
    static let cornerRadius: CGFloat = 22
}

/// A widget as the desktop shows it: its content inside the default margins, on Headroom's dark container, or
/// see-through (accented) on a translucent plate.
struct WidgetFrame<Content: View>: View {
    let size: WidgetFrameSize
    var accented = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(WidgetFrameSize.contentMargin)
            .frame(width: size.points.width, height: size.points.height)
            .environment(\.widgetRenderingMode, accented ? .accented : .fullColor)
            // Accented widgets lose their colors to the system tint: shown here without saturation.
            .saturation(accented ? 0 : 1)
            .background(
                RoundedRectangle(cornerRadius: WidgetFrameSize.cornerRadius, style: .continuous)
                    .fill(accented ? Color.white.opacity(0.12) : HeadroomTheme.panelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: WidgetFrameSize.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: WidgetFrameSize.cornerRadius, style: .continuous))
            .environment(\.colorScheme, .dark)
    }
}

/// Made-up widget files (§6.5): Claude weekly 89 % / 5-hour 14 %; Codex Plus, 5-hour 20 %, weekly 94 %, resets
/// Wed 9 AM; Copilot Pro, 512 of 1,500 credits; one Codex session "website" working at 41 %.
@MainActor
enum WidgetSamples {
    static let S = SampleData.fixed

    /// The next Wednesday, 9 AM.
    static var codexWeeklyReset: Date {
        S.calendar.nextDate(after: S.now, matching: DateComponents(hour: 9, minute: 0, weekday: 4), matchingPolicy: .nextTime)
            ?? S.now.addingTimeInterval(6 * 86_400)
    }

    static func codex(weekly: Double = 94, fiveHour: Double? = nil, age: TimeInterval = 300) -> ToolUsage {
        let observedAt = S.now.addingTimeInterval(-age)
        var limits = [ToolLimit(window: .weekly, usedPercent: weekly, resetsAt: codexWeeklyReset, observedAt: observedAt)]
        if let fiveHour {
            limits.append(ToolLimit(
                window: .fiveHour, usedPercent: fiveHour, resetsAt: S.now.addingTimeInterval(70 * 60), observedAt: observedAt
            ))
        }
        return ToolUsage(
            tool: .codex, limits: limits, hasFiveHourWindow: fiveHour != nil, status: .ok, planName: "Plus"
        )
    }

    /// The first of next month, 00:00 UTC: GitHub's reset.
    static var copilotReset: Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let month = utc.dateComponents([.year, .month], from: S.now)
        return utc.date(byAdding: .month, value: 1, to: utc.date(from: month)!)!
    }

    static func copilot(used: Double = 512, allowance: Double? = 1500, status: ToolStatus = .ok) -> ToolUsage {
        let limits = status == .ok ? [ToolLimit(
            window: .monthly, usedPercent: allowance.map { used / $0 * 100 }, used: used, allowance: allowance,
            unit: .aiCredits, resetsAt: copilotReset, observedAt: S.now.addingTimeInterval(-600)
        )] : []
        return ToolUsage(
            tool: .copilot, limits: limits, status: status, planName: allowance == nil ? nil : "Pro", account: "octocat"
        )
    }

    static func tagged(_ session: SessionInfo, _ tool: ToolID, id: String) -> SessionInfo {
        var session = session
        session.tool = tool
        session.id = id
        return session
    }

    static var codexWebsite: SessionInfo {
        var session = S.session(
            "codex-website", .working, name: "website", project: "/Users/me/code/website",
            used: 113_000, window: 258_400, model: "gpt-6-astra", minutesAgo: 2
        )
        session.context?.baselineTokens = 12_000
        return tagged(session, .codex, id: "codex:01a0beba-55ec-7ac1-84a7-16d9f0a456e0")
    }

    static var copilotHarbor: SessionInfo {
        var session = S.session("copilot-harbor", .idle, name: "harbor", project: "/Users/me/code/harbor", origin: .terminal, minutesAgo: 12)
        session.context = nil
        return tagged(session, .copilot, id: "copilot:5f0c7c1e-2b1d-4c3e-9a55-3c1f1b0e8d42")
    }

    static var claudeOnlySessions: [SessionInfo] {
        S.working + [S.waitingTerminal] + Array(S.idle.prefix(3))
    }

    static var mixedSessions: [SessionInfo] {
        ([S.working[0], codexWebsite, S.waitingTerminal, S.idle[0], copilotHarbor, S.idle[1], S.idle[2]]).sortedForDisplay()
    }

    static func claudeOnly(weekly: Double = 89, fiveHour: Double = 14, age: TimeInterval = 120) -> HeadroomSnapshot {
        S.snapshot(S.plan(weekly: weekly, fiveHour: fiveHour, age: age), claudeOnlySessions)
    }

    static var multiTool: HeadroomSnapshot {
        var snapshot = S.snapshot(S.plan(weekly: 89, fiveHour: 14), mixedSessions)
        snapshot.codex = codex()
        snapshot.copilot = copilot()
        return snapshot
    }

    static func file(
        _ snapshot: HeadroomSnapshot, writtenAgo: TimeInterval = 120, isSample: Bool = false,
        pillTool: ToolID? = .claude, showsNames: Bool = true
    ) -> WidgetSnapshotFile {
        WidgetSnapshotFile.scrubbing(
            snapshot, writtenAt: S.now.addingTimeInterval(-writtenAgo), isSample: isSample, pillTool: pillTool,
            showsSessionNames: showsNames
        )
    }

    // MARK: Widgets

    static func limits(_ file: WidgetSnapshotFile?, _ size: LimitsWidgetView.Size, choice: WidgetToolChoice = .automatic,
                       accented: Bool = false) -> some View {
        WidgetFrame(size: size == .small ? .small : .medium, accented: accented) {
            LimitsWidgetView(model: LimitsWidgetModel(file: file, choice: choice, now: S.now), size: size)
        }
    }

    static func sessions(_ file: WidgetSnapshotFile?, _ size: SessionsWidgetView.Size, accented: Bool = false) -> some View {
        WidgetFrame(size: size == .medium ? .medium : .large, accented: accented) {
            SessionsWidgetView(model: SessionsWidgetModel(file: file, now: S.now), size: size)
        }
    }
}

extension RenderScene {
    /// Every widget state of §11.3, on the review canvas (part of `RenderScene.all`).
    static var widgets: [RenderScene] {
        let W = WidgetSamples.self
        let claude = W.file(W.claudeOnly())
        let multi = W.file(W.multiTool)
        return [
            RenderScene("widget-limits-small", HStack(alignment: .top, spacing: 16) {
                W.limits(claude, .small)
                W.limits(multi, .small, choice: .codex)
                W.limits(multi, .small, choice: .copilot)
            }),
            // Codex Pro (weekly only: one ring, no inner track), Copilot without a plan (an amount, no ring fill),
            // Copilot not connected, and a tool that isn't tracked.
            RenderScene("widget-limits-small-tools", HStack(alignment: .top, spacing: 16) {
                W.limits(W.file(snapshot(codex: W.codex(weekly: 42, fiveHour: nil))), .small, choice: .codex)
                W.limits(W.file(snapshot(copilot: W.copilot(allowance: nil))), .small, choice: .copilot)
                W.limits(W.file(snapshot(copilot: W.copilot(status: .notConnected))), .small, choice: .copilot)
                W.limits(claude, .small, choice: .codex)
            }),
            RenderScene("widget-limits-medium-multi", VStack(spacing: 16) {
                W.limits(multi, .medium)
                W.limits(W.file(snapshot(codex: W.codex(weekly: 42, fiveHour: nil))), .medium)
            }),
            RenderScene("widget-limits-medium-single", VStack(spacing: 16) {
                W.limits(claude, .medium)
                W.limits(multi, .medium, choice: .codex)
                W.limits(multi, .medium, choice: .copilot)
            }),
            RenderScene("widget-sessions-medium", VStack(spacing: 16) {
                W.sessions(multi, .medium)
                W.sessions(claude, .medium)
            }),
            RenderScene("widget-sessions-large", HStack(alignment: .top, spacing: 16) {
                W.sessions(multi, .large)
                W.sessions(claude, .large)
            }),
            RenderScene("widget-names-hidden", HStack(alignment: .top, spacing: 16) {
                W.sessions(W.file(W.multiTool, showsNames: false), .medium)
            }),
            RenderScene("widget-empty", HStack(alignment: .top, spacing: 16) {
                W.limits(nil, .small)
                W.sessions(nil, .medium)
                W.sessions(W.file(W.S.snapshot(W.S.plan(weekly: 31, fiveHour: 8), [])), .medium)
            }),
            RenderScene("widget-not-running", HStack(alignment: .top, spacing: 16) {
                W.limits(W.file(W.claudeOnly(age: 3 * 3600), writtenAgo: 2 * 3600), .small)
                W.sessions(W.file(W.claudeOnly(age: 3 * 3600), writtenAgo: 2 * 3600), .medium)
            }),
            RenderScene("widget-sample", HStack(alignment: .top, spacing: 16) {
                W.limits(W.file(W.multiTool, isSample: true), .small)
                W.sessions(W.file(W.multiTool, isSample: true), .medium)
            }),
            RenderScene("widget-accented", HStack(alignment: .top, spacing: 16) {
                W.limits(W.file(W.claudeOnly(weekly: 97, fiveHour: 80)), .small, accented: true)
                W.limits(multi, .medium, accented: true)
                W.sessions(multi, .large, accented: true)
            }),
        ]
    }

    /// Claude untracked, with only the given tools.
    private static func snapshot(codex: ToolUsage? = nil, copilot: ToolUsage? = nil) -> HeadroomSnapshot {
        let S = WidgetSamples.S
        var snapshot = S.snapshot(.empty, codex == nil ? [] : [WidgetSamples.codexWebsite])
        snapshot.claudeTracked = false
        snapshot.codex = codex
        snapshot.copilot = copilot
        return snapshot
    }
}

// MARK: - Store screenshot 07

/// A desktop with the three widgets: small Limits, medium Sessions and large Sessions (store 07, the widgets
/// feature snippet).
struct WidgetDesktopGrid: View {
    static let spacing: CGFloat = 16

    let file: WidgetSnapshotFile

    var body: some View {
        let W = WidgetSamples.self
        HStack(alignment: .top, spacing: Self.spacing) {
            W.limits(file, .small)
            VStack(spacing: Self.spacing) {
                W.sessions(file, .medium)
                W.sessions(file, .large)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
    }
}

extension StoreScreenshot {
    /// 07: "Widgets for your desktop." Last in `StoreScreenshot.all`, after 06.
    static var widgets: StoreScreenshot {
        let snapshot = WidgetSamples.multiTool
        let file = WidgetSamples.file(snapshot)
        return StoreScreenshot("07-widgets", ZStack(alignment: .topLeading) {
            Backdrop(base: 0x0B0C10, fields: [
                .init(color: 0x3558C8, x: 0.92, y: 0.25, radius: 560, opacity: 0.30),
                .init(color: 0x5DCAA5, x: 0.06, y: 0.92, radius: 520, opacity: 0.26),
                .init(color: 0xEF9F27, x: 0.55, y: 0.02, radius: 340, opacity: 0.10),
            ])
            MenuBar(pill: PillView(snapshot: snapshot, moment: nil, now: WidgetSamples.S.now, height: PillMetrics.standardHeight), highlighted: false)
            Caption(
                title: "Widgets for\nyour desktop.",
                detail: "Add Limits and Sessions widgets to your desktop or Notification Center: the same rings and sessions as the panel."
            ) {
                EmptyView()
            }
            .frame(width: 330, alignment: .leading)
            .padding(.leading, StoreDesktop<EmptyView, EmptyView, EmptyView>.captionLeading)
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.top, MenuBarMetrics.height)
            .padding(.bottom, 44)
            WidgetDesktopGrid(file: file)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 36)
                .padding(.top, MenuBarMetrics.height)
        }
        .frame(width: StoreScreenshot.points.width, height: StoreScreenshot.points.height)
        .environment(\.colorScheme, .dark)
        .environment(\.frozenPulsePhase, 0.35))
    }
}
