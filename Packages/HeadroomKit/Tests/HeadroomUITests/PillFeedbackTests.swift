import AppKit
import Foundation
import HeadroomModel
import SwiftUI
import Testing
@testable import HeadroomUI

/// The pill's 1.1 §14 changes: the needs-you rest state (§14.4), the taller pill (§14.6 note 8) and smooth motion
/// (§14.6 note 7).
@Suite struct NeedsYouAttentionTests {
    @Test func oneSessionShowsItsNameAndMoreTheirCount() throws {
        let one = try #require(NeedsYouAttention(names: ["harbor"]))
        #expect(one.name == "harbor")
        #expect(one.status == nil)
        #expect(one.text == "harbor")
        let two = try #require(NeedsYouAttention(names: ["harbor", "atlas"]))
        #expect(two.name == nil)
        #expect(two.text == "2 need you")
        #expect(NeedsYouAttention(names: ["  "])?.text == "A session")
        #expect(NeedsYouAttention(names: []) == nil)
    }

    @Test func voiceOverSaysWhoNeedsInput() {
        #expect(NeedsYouAttention(names: ["harbor"])?.spoken == "harbor needs your input")
        #expect(NeedsYouAttention(names: ["harbor", "atlas"])?.spoken == "2 sessions need your input: harbor, atlas")
    }
}

@Suite struct PillAttentionModelTests {
    let now = Fixture.now
    let sessions = [
        Fixture.session("w", .working),
        Fixture.session("t1", .waitingForInput, name: "harbor"),
        Fixture.session("t2", .waitingForInput, name: "atlas"),
    ]

    private func model(attention: [String] = [], dismissed: Set<String> = [], moment: Moment? = nil) -> PillModel {
        PillModel(
            snapshot: Fixture.snapshot(plan: Fixture.plan(weekly: 89, fiveHour: 14), sessions: sessions), moment: moment,
            now: now, attention: NeedsYouAttention(names: attention), dismissedIDs: dismissed
        )
    }

    @Test func modes() {
        #expect(model().mode == .normal)
        #expect(model(attention: ["harbor"]).mode == .attention)
        // Other moments play over the rest state.
        #expect(model(attention: ["harbor"], moment: .sessionFinished(sessionID: "w", name: "ledger")).mode == .moment)
    }

    @Test func voiceOverStartsWithWhoNeedsYou() {
        let label = model(attention: ["harbor"]).accessibilityLabel
        #expect(label.hasPrefix("harbor needs your input. 3 active sessions, 2 need input."), "\(label)")
        // A moment says it itself.
        #expect(!model(attention: ["harbor"], moment: .sessionNeedsInput(sessionID: "t1", name: "harbor")).accessibilityLabel
            .contains("needs your input"))
    }

    /// Dismissed waits leave the dot and the count (1.1 §14.4).
    @Test func dismissedWaitsLeaveTheDotAndTheCount() {
        #expect(model().dot == .waiting)
        #expect(model().count == 3)
        let one = model(dismissed: ["t1"])
        #expect(one.dot == .waiting)
        #expect(one.count == 2)
        let both = model(dismissed: ["t1", "t2"])
        #expect(both.dot == .working)
        #expect(both.count == 1)
        #expect(both.accessibilityLabel.hasPrefix("1 active session."), "\(both.accessibilityLabel)")
    }

    @Test func dismissingAWorkingSessionChangesNothing() {
        #expect(model(dismissed: ["w"]) == model())
    }

    @Test func nameCapIsNarrowerWithOneGaugePerTool() {
        let multi = Fixture.tools(
            claude: Fixture.plan(weekly: 40, fiveHour: 10), codex: Fixture.codex(weekly: 30, fiveHour: 5),
            sessions: [Fixture.toolSession("t", .waitingForInput, tool: .claude, name: "harbor")]
        )
        let single = PillModel(snapshot: multi, moment: nil, now: now, attention: NeedsYouAttention(names: ["harbor"]),
                               height: PillMetrics.minimumHeight)
        let perTool = PillModel(snapshot: multi, moment: nil, now: now, gaugePerTool: true,
                                attention: NeedsYouAttention(names: ["harbor"]), height: PillMetrics.minimumHeight)
        #expect(single.maxAttentionNameWidth == 88)
        #expect(perTool.maxAttentionNameWidth == 56)
    }
}

@Suite struct PillMetricsTests {
    @Test func twentyTwoPointsIsOnePointZero() {
        let metrics = PillMetrics(height: 22)
        #expect(metrics.gaugeSize == 18)
        #expect(metrics.dotDiameter == 7)
        #expect(metrics.fontSize == 12)
        #expect(metrics.horizontalPadding == 9)
        #expect(metrics.spacing == 7)
        #expect(metrics.dotSpacing == 5)
        #expect(metrics.maxMomentTextWidth == 212)
        #expect(metrics.maxAttentionNameWidth == 88)
        #expect(metrics.maxAttentionNameWidthPerTool == 56)
        #expect(metrics.gaugeStyle == .pill)
    }

    @Test func everythingScalesWithTheHeight() {
        #expect(PillMetrics().height == 22)
        let standard = PillMetrics(height: PillMetrics.standardHeight)
        #expect(standard.height == 24)
        #expect(standard.gaugeSize == 20)
        #expect(standard.fontSize == 13)
        #expect(standard.dotDiameter == 8)
        let tall = PillMetrics(height: 30)
        #expect(tall.gaugeSize == 24)
        #expect(tall.fontSize == 16)
        #expect(tall.horizontalPadding == 12)
    }

    /// Gauges are an even number of points, so their centre is on the pixel grid at every scale.
    @Test(arguments: [22.0, 23, 24, 25, 27, 30, 31, 34])
    func gaugesAreAnEvenNumberOfPoints(height: Double) {
        let size = PillMetrics(height: height).gaugeSize
        #expect(size.truncatingRemainder(dividingBy: 2) == 0, "\(size)")
    }

    @Test func neverUnderTwentyTwoPoints() {
        #expect(PillMetrics(height: 18).height == 22)
        #expect(PillMetrics(height: .nan).height == 22)
        #expect(PillMetrics.height(forMenuBar: 24) == 22)
        #expect(PillMetrics.height(forMenuBar: 30) == 24)
        #expect(PillMetrics.height(forMenuBar: 37.5) == 31)
    }
}

@Suite struct PillMotionTests {
    typealias Motion = PillMotion<String>

    private func target(_ content: String, _ mode: PillModel.Mode, _ width: CGFloat) -> Motion.Target {
        Motion.Target(content: content, mode: mode, width: width)
    }

    /// Width, title and gauges move together; there is no hidden-text interval between separate steps.
    @Test func growingAndShrinkingEachUseOneTransition() {
        let grow = Motion.steps(from: target("pill", .normal, 97), to: target("moment", .moment, 166), reduceMotion: false)
        #expect(grow == [.init(content: "moment", width: 166, duration: Motion.transitionDuration)])
        let shrink = Motion.steps(from: target("moment", .moment, 166), to: target("rest", .attention, 135), reduceMotion: false)
        #expect(shrink == [.init(content: "rest", width: 135, duration: Motion.transitionDuration)])
    }

    @Test func aWidthChangeWithinOneLayoutAlsoAnimates() {
        let steps = Motion.steps(from: target("short", .attention, 97), to: target("long title", .attention, 166), reduceMotion: false)
        #expect(steps == [.init(content: "long title", width: 166, duration: Motion.transitionDuration)])
    }

    @Test func sameLayoutAndReduceMotionChangeAtOnce() {
        #expect(Motion.steps(from: target("2", .normal, 97), to: target("3", .normal, 97), reduceMotion: false)
            == [.init(content: "3", width: 97, duration: 0)])
        #expect(Motion.steps(from: target("pill", .normal, 97), to: target("moment", .moment, 166), reduceMotion: true)
            == [.init(content: "moment", width: 166, duration: 0)])
    }

    /// Pills that arrive during a transition wait; only the newest is kept, and it starts from where the running
    /// transition ends.
    @Test func updatesWhileAnimatingAreCoalesced() {
        var motion = Motion()
        #expect(motion.show(target("pill", .normal, 97), reduceMotion: false).map(\.duration) == [0])
        #expect(!motion.isRunning)

        let grow = motion.show(target("moment", .moment, 166), reduceMotion: false)
        #expect(grow.count == 1)
        #expect(motion.isRunning)

        #expect(motion.show(target("pill 2", .normal, 97), reduceMotion: false).isEmpty)
        #expect(motion.show(target("pill 3", .normal, 105), reduceMotion: false).isEmpty)
        #expect(motion.pending?.content == "pill 3")

        let next = motion.finished(reduceMotion: false)
        #expect(next.count == 1)
        #expect(next.last == .init(content: "pill 3", width: 105, duration: Motion.transitionDuration))
        #expect(motion.pending == nil)
        #expect(motion.shown?.content == "pill 3")

        #expect(motion.finished(reduceMotion: false).isEmpty)
        #expect(!motion.isRunning)
    }

    @Test func nothingNewNothingToDo() {
        var motion = Motion()
        _ = motion.show(target("pill", .normal, 97), reduceMotion: false)
        #expect(motion.show(target("pill", .normal, 97), reduceMotion: false).isEmpty)
        #expect(!motion.isRunning)
    }

    @Test func easing() {
        #expect(Motion.progress(0) == 0)
        #expect(Motion.progress(1) == 1)
        #expect(Motion.progress(2) == 1)
        #expect(Motion.progress(0.5) == 0.875)
        #expect(Motion.animation(duration: 0) == nil)
        #expect(Motion.animation(duration: 0.3) != nil)
    }
}

/// Measured pills (1.1 §14.4, §14.6).
@MainActor @Suite struct PillLayoutFeedbackTests {
    let now = Fixture.now

    private func width(_ view: some View) -> CGFloat {
        NSHostingView(rootView: view).fittingSize.width
    }

    private func pill(attention: [String], height: CGFloat = PillMetrics.minimumHeight, gaugePerTool: Bool = false) -> PillView {
        let snapshot = Fixture.tools(
            claude: Fixture.plan(weekly: 89, fiveHour: 14), codex: gaugePerTool ? Fixture.codex(weekly: 30, fiveHour: 5) : nil,
            sessions: [Fixture.toolSession("t", .waitingForInput, tool: .claude)]
        )
        return PillView(
            snapshot: snapshot, moment: nil, now: now, gaugePerTool: gaugePerTool,
            attention: NeedsYouAttention(names: attention), height: height
        )
    }

    /// Wide names are cut at 88 pt, so the rest state stays well under the moment's width (the spec's ~185 pt).
    @Test(arguments: ["harbor", String(repeating: "W", count: 30), "修复登录错误并更新文档以及测试用例和发布说明内容",
                      String(repeating: "🚀", count: 30)])
    func restStateStaysNarrow(name: String) {
        let rest = width(pill(attention: [name]))
        #expect(rest <= 186, "\(name): \(rest) pt")
        #expect(width(pill(attention: [name, "atlas"])) <= 186)
    }

    @Test func longNamesAllCapAtOneWidth() {
        let latin = width(pill(attention: [String(repeating: "W", count: 30)]))
        let emoji = width(pill(attention: [String(repeating: "🚀", count: 30)]))
        #expect(abs(latin - emoji) < 1)
        #expect(width(pill(attention: ["harbor"])) < latin)
    }

    @Test func oneGaugePerToolCapsTheNameNarrower() {
        let wide = String(repeating: "W", count: 30)
        let single = width(pill(attention: [wide])) - width(pill(attention: ["W"]))
        let perTool = width(pill(attention: [wide], gaugePerTool: true)) - width(pill(attention: ["W"], gaugePerTool: true))
        #expect(perTool < single - 25, "name room \(single) vs \(perTool)")
    }

    /// The status item is sized to the pill's fitting width; given more, `fillsWidth` stretches the capsule and a
    /// plain pill stays its own size.
    @Test func fillsWidthFollowsTheItem() throws {
        let snapshot = Fixture.snapshot(sessions: [Fixture.session("a", .working)])
        let natural = width(PillView(snapshot: snapshot, moment: nil, now: now))
        #expect(width(PillView(snapshot: snapshot, moment: nil, now: now, fillsWidth: true)) == natural)

        func renderedWidth(_ view: some View) throws -> Int {
            let renderer = ImageRenderer(content: view.frame(width: natural + 60, alignment: .leading))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            // The rightmost column the capsule paints.
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            bytes.withUnsafeMutableBytes { buffer in
                CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                          bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                    .draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            let row = image.height / 2
            return (0..<image.width).last { bytes[(row * image.width + $0) * 4 + 3] > 0 }.map { $0 + 1 } ?? 0
        }
        let filled = try renderedWidth(PillView(snapshot: snapshot, moment: nil, now: now, fillsWidth: true))
        let plain = try renderedWidth(PillView(snapshot: snapshot, moment: nil, now: now))
        #expect(filled == Int(natural) + 60, "natural \(natural), filled \(filled), plain \(plain)")
        #expect(plain <= Int(natural.rounded(.up)) + 1, "natural \(natural), filled \(filled), plain \(plain)")
    }
}

@MainActor @Suite struct RingKeyTests {
    @Test func theOtherRingDimsWhileARowIsHovered() {
        #expect(RingGauge.ringOpacity(.outer, emphasis: nil) == 1)
        #expect(RingGauge.ringOpacity(.inner, emphasis: nil) == 1)
        #expect(RingGauge.ringOpacity(.outer, emphasis: .outer) == 1)
        #expect(RingGauge.ringOpacity(.inner, emphasis: .outer) == 0.28)
        #expect(RingGauge.ringOpacity(.outer, emphasis: .inner) == 0.28)
    }

    @Test func glyphFitsItsBox() {
        #expect(RingKeyGlyph.outerRadius + RingKeyGlyph.lineWidth / 2 <= RingKeyGlyph.size / 2)
        #expect(RingKeyGlyph.innerRadius + RingKeyGlyph.lineWidth / 2 < RingKeyGlyph.outerRadius - RingKeyGlyph.lineWidth / 2)
    }

    @Test func claudeRowsNameTheirRing() {
        let model = PanelModel(snapshot: Fixture.snapshot(plan: Fixture.plan(weekly: 89, fiveHour: 14)), now: Fixture.now)
        #expect(model.weekly.ring == .outer)
        #expect(model.fiveHour.ring == .inner)
        #expect(model.header.rows.map(\.ring) == [.outer, .inner])
    }

    /// Two windows: a key per row. One window: the gauge has one ring, so no key (the columns stay aligned).
    @Test func toolRowsHaveKeysOnlyWithTwoWindows() throws {
        let plus = PanelModel(snapshot: Fixture.tools(claude: nil, codex: Fixture.codex(weekly: 94, fiveHour: 20)), now: Fixture.now)
        #expect(plus.header.rows.map(\.ring) == [.outer, .inner])
        let pro = PanelModel(snapshot: Fixture.tools(claude: nil, codex: Fixture.codex(weekly: 42, fiveHour: nil)), now: Fixture.now)
        #expect(pro.header.rows.map(\.ring) == [nil])

        let multi = PanelModel(snapshot: Fixture.tools(
            claude: Fixture.plan(weekly: 40, fiveHour: 10), codex: Fixture.codex(weekly: 94, fiveHour: 20),
            copilot: Fixture.copilot(used: 512)
        ), now: Fixture.now)
        let codex = try #require(multi.toolRows.first { $0.tool == .codex })
        let copilot = try #require(multi.toolRows.first { $0.tool == .copilot })
        #expect(codex.lines.map(\.ring) == [.outer, .inner])
        #expect(copilot.lines.map(\.ring) == [nil])
    }
}
