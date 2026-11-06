import AppKit
import HeadroomModel
import HeadroomSamples
import HeadroomUI
import SwiftUI

/// The Mac App Store screenshots (`headroom-render --store <dir>`): 2880×1800 (16:10), opaque sRGB.
///
/// Each one is a made-up desktop: a procedural dark backdrop (no wallpapers, no logos), a menu bar
/// with neutral glyphs and the pill in it, the open panel hanging from the pill, and a caption on
/// the left. The desktop is laid out at 1024×640 pt and rendered at 2.8125×, so the pill and panel
/// read at 1.4× their size on a 1440×900 screen: legible in the store's thumbnails. All data comes from
/// `SampleData.fixed`.
@MainActor
struct StoreScreenshot {
    static let points = CGSize(width: 1024, height: 640)
    /// 1024 × 2.8125 = 2880, 640 × 2.8125 = 1800.
    static let scale: CGFloat = 2.8125

    let name: String
    let content: AnyView

    init(_ name: String, _ content: some View) {
        self.name = name
        self.content = AnyView(content)
    }

    func write(to url: URL) throws {
        try ImageExport.writeOpaque(content, points: Self.points, scale: Self.scale, to: url)
    }
}

extension StoreScreenshot {
    static let S = SampleData.fixed

    /// 01–05 use Claude-only data, so they look as in 1.0 (05 has the 1.1 caption); 06 shows the other tools.
    static var all: [StoreScreenshot] {
        [glance, sessions, nearLimit, terminal, privacy, tools, widgets]
    }

    // MARK: 1. Your AI limits, one glance away.

    static var glance: StoreScreenshot {
        let snapshot = S.snapshot(
            S.plan(weekly: 58, fiveHour: 41),
            S.working + [S.waitingTerminal] + Array(S.idle.prefix(4))
        )
        return StoreScreenshot("01-glance", StoreDesktop(
            backdrop: .init(base: 0x0B0D10, fields: [
                .init(color: 0x2FA37F, x: 0.86, y: 0.10, radius: 520, opacity: 0.42),
                .init(color: 0x3558C8, x: 0.08, y: 0.95, radius: 560, opacity: 0.32),
                .init(color: 0x5DCAA5, x: 0.40, y: 0.55, radius: 300, opacity: 0.10),
            ]),
            pill: PillView(snapshot: snapshot, moment: nil, now: S.now, height: PillMetrics.standardHeight),
            panel: PanelView(snapshot: snapshot, now: S.now, actions: .none),
            caption: Caption(
                title: "Your AI limits,\none glance away.",
                detail: "Two rings in the menu bar: the outer one is your weekly limit, the inner one your 5-hour limit. Click for the details."
            ) {
                GaugeLegend(plan: snapshot.plan, now: S.now)
            }
        ))
    }

    // MARK: 2. Every session, working or waiting.

    static var sessions: StoreScreenshot {
        let sessions = [
            S.session("w1", .working, name: "Refactor invoice export", project: "/Users/me/code/ledger", used: 720_000),
            S.session("w3", .working, name: "Migrate sign-in to passkeys", project: "/Users/me/code/atlas",
                      used: 412_000, minutesAgo: 2),
            S.session("w2", .working, name: "Draft onboarding emails", project: "/Users/me/code/website",
                      used: 28_000, window: 200_000, model: "claude-haiku-4-5", minutesAgo: 3),
            S.waitingTerminal,
            S.session("n2", .waitingForInput, name: "Review pricing copy", project: "/Users/me/code/website",
                      used: 96_000, window: 200_000, minutesAgo: 2),
        ] + Array(S.idle.prefix(3))
        let snapshot = S.snapshot(S.plan(weekly: 47, fiveHour: 22), sessions)
        return StoreScreenshot("02-sessions", StoreDesktop(
            backdrop: .init(base: 0x0A0D0C, fields: [
                .init(color: 0x5DCAA5, x: 0.92, y: 0.35, radius: 560, opacity: 0.34),
                .init(color: 0xEF9F27, x: 0.05, y: 0.05, radius: 420, opacity: 0.16),
                .init(color: 0x1E6B8C, x: 0.20, y: 1.00, radius: 520, opacity: 0.30),
            ]),
            pill: PillView(snapshot: snapshot, moment: nil, now: S.now, height: PillMetrics.standardHeight),
            panel: PanelView(snapshot: snapshot, now: S.now, actions: .none),
            caption: Caption(
                title: "Every session,\nworking or waiting.",
                detail: "See at a glance which sessions are busy, which are waiting for an answer from you, and which are done."
            ) {
                SessionLegend()
            }
        ))
    }

    // MARK: 3. Know before you hit the limit.

    static var nearLimit: StoreScreenshot {
        let snapshot = S.snapshot(S.plan(weekly: 91, fiveHour: 97), [S.working[0], S.waitingTerminal] + Array(S.idle.prefix(2)))
        let moment = Moment.limitCrossed(kind: .weekly, percent: 90)
        return StoreScreenshot("03-near-limit", StoreDesktop(
            backdrop: .init(base: 0x100B0A, fields: [
                .init(color: 0xE24B4A, x: 0.95, y: 0.15, radius: 520, opacity: 0.34),
                .init(color: 0xEF9F27, x: 0.10, y: 0.90, radius: 560, opacity: 0.28),
                .init(color: 0x6B2A1E, x: 0.45, y: 0.40, radius: 360, opacity: 0.20),
            ]),
            pill: PillView(snapshot: snapshot, moment: moment, now: S.now, height: PillMetrics.standardHeight),
            panel: PanelView(snapshot: snapshot, now: S.now, actions: .none),
            caption: Caption(
                title: "Know before you\nhit the limit.",
                detail: "The number turns amber from 75% and red from 95%, and the menu bar tells you when a limit passes 90%."
            ) {
                PillShowcase(items: [
                    .init(label: "From 75%", snapshot: S.snapshot(S.plan(weekly: 82, fiveHour: 30), [S.working[0]]), moment: nil),
                    .init(label: "From 95%", snapshot: S.snapshot(S.plan(weekly: 97, fiveHour: 62), [S.working[0]]), moment: nil),
                    .init(label: "At 90%", snapshot: snapshot, moment: moment),
                ], now: S.now)
            }
        ))
    }

    // MARK: 4. Desktop app and terminal.

    static var terminal: StoreScreenshot {
        let sessions = [
            S.session("w1", .working, name: "Refactor invoice export", project: "/Users/me/code/ledger", used: 720_000),
            S.session("t2", .working, name: "atlas", project: "/Users/me/code/atlas", origin: .terminal,
                      used: 188_000, window: 1_000_000, minutesAgo: 1),
            S.waitingTerminal,
            S.session("i2", .idle, name: "Update pricing table", project: "/Users/me/code/website",
                      used: 142_000, window: 200_000, minutesAgo: 9),
            S.session("t3", .idle, name: "website", project: "/Users/me/code/website", origin: .terminal,
                      used: 64_000, window: 200_000, minutesAgo: 22),
        ]
        let snapshot = S.snapshot(S.plan(weekly: 54, fiveHour: 29, source: .terminal), sessions)
        return StoreScreenshot("04-terminal", StoreDesktop(
            backdrop: .init(base: 0x0A0B11, fields: [
                .init(color: 0x4B5BD6, x: 0.90, y: 0.20, radius: 560, opacity: 0.34),
                .init(color: 0x5DCAA5, x: 0.02, y: 0.98, radius: 520, opacity: 0.24),
                .init(color: 0x8A5CF6, x: 0.45, y: 0.05, radius: 360, opacity: 0.14),
            ]),
            pill: PillView(snapshot: snapshot, moment: nil, now: S.now, height: PillMetrics.standardHeight),
            panel: PanelView(snapshot: snapshot, now: S.now, actions: .none),
            caption: Caption(
                title: "Desktop app\nand terminal.",
                detail: "Works with Claude Code. Desktop sessions show up on their own; terminal sessions after one click."
            ) {
                SettingsCard()
            }
        ))
    }

    // MARK: 5. No account. Local by default.

    static var privacy: StoreScreenshot {
        let snapshot = S.snapshot(S.plan(weekly: 31, fiveHour: 12), [S.working[1]] + Array(S.idle.prefix(3)))
        return StoreScreenshot("05-privacy", StoreDesktop(
            backdrop: .init(base: 0x0C0B12, fields: [
                .init(color: 0x7A5AF8, x: 0.88, y: 0.12, radius: 540, opacity: 0.30),
                .init(color: 0x2C7DA0, x: 0.05, y: 0.92, radius: 560, opacity: 0.26),
                .init(color: 0x5DCAA5, x: 0.55, y: 0.95, radius: 320, opacity: 0.10),
            ]),
            pill: PillView(snapshot: snapshot, moment: nil, now: S.now, height: PillMetrics.standardHeight),
            panel: PanelView(snapshot: snapshot, now: S.now, actions: .none),
            caption: Caption(
                title: "No account.\nLocal by default.",
                detail: "Claude and Codex work from files already on your Mac. Copilot usage is optional and talks only to GitHub."
            ) {
                PrivacyList()
            }
        ))
    }

    // MARK: 6. More tools, one panel.

    static var tools: StoreScreenshot {
        var snapshot = S.multiTool
        snapshot.plan = S.plan(weekly: 58, fiveHour: 41)
        snapshot.codex = S.codex(weekly: 36)
        var nearLimit = snapshot
        nearLimit.codex = S.codex(weekly: 94)
        return StoreScreenshot("06-tools", StoreDesktop(
            backdrop: .init(base: 0x0B0C10, fields: [
                .init(color: 0x3558C8, x: 0.90, y: 0.18, radius: 560, opacity: 0.34),
                .init(color: 0x5DCAA5, x: 0.06, y: 0.92, radius: 540, opacity: 0.26),
                .init(color: 0x8A5CF6, x: 0.50, y: 0.02, radius: 360, opacity: 0.14),
            ]),
            pill: PillView(snapshot: snapshot, moment: nil, now: S.now, height: PillMetrics.standardHeight),
            panel: PanelView(snapshot: snapshot, now: S.now, actions: .none),
            caption: Caption(
                title: "More tools,\none panel.",
                detail: "OpenAI Codex limits and sessions next to Claude's, and this month's GitHub Copilot usage if you connect it."
            ) {
                PillShowcase(items: [
                    .init(label: "Claude", snapshot: snapshot, moment: nil),
                    .init(label: "Codex", snapshot: nearLimit, moment: nil, tool: .codex),
                    .init(label: "Per tool", snapshot: nearLimit, moment: nil, gaugePerTool: true),
                ], now: S.now)
            }
        ))
    }
}

// MARK: - Desktop

/// Backdrop, menu bar with the pill, the open panel and the caption.
struct StoreDesktop<Pill: View, Panel: View, Extra: View>: View {
    static var captionWidth: CGFloat { 372 }
    static var captionLeading: CGFloat { 60 }

    let backdrop: Backdrop
    let pill: Pill
    let panel: Panel
    let caption: Caption<Extra>
    /// The status item is highlighted while its panel is open.
    var highlighted = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop
            MenuBar(pill: pill, highlighted: highlighted)
            caption
                .frame(width: Self.captionWidth, alignment: .leading)
                .padding(.leading, Self.captionLeading)
                .frame(maxHeight: .infinity, alignment: .center)
                .padding(.top, MenuBarMetrics.height)
                .padding(.bottom, 44)
        }
        .overlayPreferenceValue(StatusItemBoundsKey.self) { anchor in
            // Right-aligned under the status item, 6 pt below the menu bar, like PanelPlacement.
            GeometryReader { proxy in
                if let anchor {
                    let item = proxy[anchor]
                    panel
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 18)
                        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.trailing, proxy.size.width - item.maxX)
                        .padding(.top, MenuBarMetrics.height + 6)
                }
            }
        }
        .frame(width: StoreScreenshot.points.width, height: StoreScreenshot.points.height)
        .environment(\.colorScheme, .dark)
        .environment(\.frozenPulsePhase, 0.35)
    }
}

/// The status item's frame in the menu bar, for hanging the panel from it.
struct StatusItemBoundsKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// A dark gradient with a few soft color fields. Procedural: no photos, no wallpapers.
struct Backdrop: View {
    struct Field {
        let color: UInt32
        /// Center, as a fraction of the canvas.
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
        let opacity: Double
    }

    let base: UInt32
    let fields: [Field]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color(hex: base)
                LinearGradient(
                    colors: [Color.white.opacity(0.035), Color.black.opacity(0.25)],
                    startPoint: .top, endPoint: .bottom
                )
                ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                    RadialGradient(
                        colors: [
                            Color(hex: field.color).opacity(field.opacity),
                            Color(hex: field.color).opacity(field.opacity * 0.45),
                            Color(hex: field.color).opacity(0),
                        ],
                        center: UnitPoint(x: field.x, y: field.y),
                        startRadius: 0,
                        endRadius: field.radius
                    )
                }
                Grain(seed: base)
                    .opacity(0.5)
                // A soft vignette keeps the edges quiet.
                RadialGradient(
                    colors: [.clear, Color.black.opacity(0.35)],
                    center: .center, startRadius: size.width * 0.35, endRadius: size.width * 0.75
                )
            }
        }
    }
}

/// Fine noise over the gradients so they don't band in 8 bits.
struct Grain: View {
    let seed: UInt32

    var body: some View {
        Canvas { context, size in
            var state = UInt64(seed) | 1
            func next() -> Double {
                // xorshift64*
                state ^= state >> 12
                state ^= state << 25
                state ^= state >> 27
                return Double((state &* 2_685_821_657_736_338_717) >> 11) / Double(1 << 53)
            }
            let step: CGFloat = 1.5
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let value = next()
                    if value > 0.55 {
                        let white = value > 0.78
                        context.fill(
                            Path(CGRect(x: x, y: y, width: 0.75, height: 0.75)),
                            with: .color(white ? Color.white.opacity(0.035) : Color.black.opacity(0.05))
                        )
                    }
                    x += step
                }
                y += step
            }
        }
    }
}

/// A macOS-like menu bar: a neutral mark and menu titles on the left, the pill and status glyphs
/// on the right. No Apple logo, no third-party icons.
enum MenuBarMetrics {
    /// A 30 pt menu bar, as Nio's measured: the 24 pt pill with 3 pt above and below (1.1 §14.6).
    static let height: CGFloat = 30
}

struct MenuBar<Pill: View>: View {
    let pill: Pill
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 18) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 13, weight: .medium))
                Text("Editor").fontWeight(.bold)
                ForEach(["File", "Edit", "View", "Window", "Help"], id: \.self) { title in
                    Text(title).fontWeight(.regular)
                }
            }
            .padding(.leading, 18)

            Spacer(minLength: 0)

            // Other status items sit on both sides, the way macOS lays them out.
            HStack(spacing: 15) {
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
            }
            .padding(.trailing, 11)

            pill
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(highlighted ? 0.2 : 0))
                )
                .anchorPreference(key: StatusItemBoundsKey.self, value: .bounds) { $0 }
                .padding(.trailing, 11)

            HStack(spacing: 15) {
                Image(systemName: "switch.2")
                Text("Thu 2:10 PM")
                    .monospacedDigit()
                    .fixedSize()
            }
            .padding(.trailing, 16)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.92))
        .frame(height: MenuBarMetrics.height)
        .frame(maxWidth: .infinity)
        .background(
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.32)
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
            }
        )
    }
}

// MARK: - Caption

struct Caption<Extra: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(HeadroomTheme.working).frame(width: 7, height: 7)
                Text("HEADROOM")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(Color.white.opacity(0.62))
            }
            .padding(.bottom, 18)
            Text(title)
                .font(.system(size: 40, weight: .bold))
                .tracking(-0.8)
                .lineSpacing(2)
                .foregroundStyle(
                    LinearGradient(colors: [Color.white, Color(hex: 0xD9D7CF)], startPoint: .top, endPoint: .bottom)
                )
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)
            Text(detail)
                .font(.system(size: 16))
                .lineSpacing(4)
                .foregroundStyle(Color(hex: 0xB4B2AA))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360, alignment: .leading)
                .padding(.bottom, 26)
            extra
        }
    }
}

/// A rounded, faintly lit card behind caption extras.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}

/// 1: the two rings, labeled.
struct GaugeLegend: View {
    let plan: PlanUsage
    let now: Date

    var body: some View {
        Card {
            HStack(spacing: 16) {
                RingGauge(gauge: GaugeModel(plan: plan, now: now), style: .panel)
                    .scaleEffect(0.78)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 8) {
                    legendRow(color: HeadroomTheme.normal, label: "Outer ring", value: "Weekly limit")
                    legendRow(color: HeadroomTheme.normal.opacity(0.75), label: "Inner ring", value: "5-hour limit")
                }
            }
        }
    }

    private func legendRow(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HeadroomTheme.primaryText)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0xA3A19A))
        }
    }
}

/// 2: the three session states.
struct SessionLegend: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                row(.working, "Working", "busy right now")
                row(.waiting, "Needs you", "waiting for your answer")
                row(.idle, "Idle", "done for now")
                HStack(spacing: 10) {
                    ContextBarSample(fraction: 0.72)
                        .frame(width: 18)
                    Text("Context")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HeadroomTheme.primaryText)
                    Text("how full each session's window is")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: 0xA3A19A))
                }
            }
        }
    }

    private func row(_ state: DotState, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            PulsingDot(state: state, diameter: 9)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HeadroomTheme.primaryText)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0xA3A19A))
        }
    }
}

/// A short context bar, as in the panel's session rows.
struct ContextBarSample: View {
    let fraction: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(HeadroomTheme.track)
            Capsule().fill(HeadroomTheme.normal).frame(width: 18 * fraction)
        }
        .frame(width: 18, height: 4)
    }
}

/// 3: pills in their warning states, enlarged.
struct PillShowcase: View {
    struct Item {
        let label: String
        let snapshot: HeadroomSnapshot
        let moment: Moment?
        /// "Rings show" (nil = Automatic) and "One gauge per tool".
        var tool: ToolID? = nil
        var gaugePerTool = false
    }

    let items: [Item]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 14) {
                    Text(item.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0xA3A19A))
                        .frame(width: 70, alignment: .leading)
                    PillView(
                        snapshot: item.snapshot, moment: item.moment, now: now, tool: item.tool, gaugePerTool: item.gaugePerTool,
                        height: PillMetrics.standardHeight
                    )
                        .scaleEffect(1.45, anchor: .leading)
                        .frame(height: 34, alignment: .leading)
                }
            }
        }
    }
}

/// 4: Settings › Terminal, drawn (ImageRenderer can't draw AppKit controls). The texts are the app's
/// own (`TerminalConnectionRow`, `TerminalBridgePresentation`), so the screenshot shows what ships.
struct SettingsCard: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 7) {
                    Circle().fill(Color(hex: 0xFF5F57)).frame(width: 10, height: 10)
                    Circle().fill(Color(hex: 0x4A4A4C)).frame(width: 10, height: 10)
                    Circle().fill(Color(hex: 0x4A4A4C)).frame(width: 10, height: 10)
                    Spacer()
                }
                Text("Headroom Settings")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .frame(height: 30)

            VStack(alignment: .leading, spacing: 6) {
                Text("Terminal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.leading, 4)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Terminal sessions")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(0.92))
                            Text("Connected")
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
                    Text("Lets Headroom see sessions you run with claude in a terminal, and exact limit reset times. Connect adds a status line and hooks to ~/.claude/settings.json, backing the file up the first time. New terminal sessions pick it up.")
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
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .frame(width: 372)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x232325)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 22, x: 0, y: 12)
    }
}

/// 5: what Headroom doesn't do.
struct PrivacyList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("person.crop.circle.badge.xmark", "No account", "nothing to sign up for")
            row("internaldrive", "Local by default", "only Copilot usage talks to GitHub, if you connect it")
            row("hand.raised.fill", "No data collected", "no analytics, no tracking")
        }
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HeadroomTheme.working)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.07)))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HeadroomTheme.primaryText)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(hex: 0xA3A19A))
            }
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
