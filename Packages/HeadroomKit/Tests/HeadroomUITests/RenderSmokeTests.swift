import AppKit
import HeadroomModel
import SwiftUI
import Testing
@testable import HeadroomUI

@MainActor @Suite struct RenderSmokeTests {
    let now = Fixture.now

    private func render(_ view: some View) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.cgImage
    }

    /// 1.0's 22 pt by default and at the least, and as tall as the app asks above that (1.1 §14.6).
    @Test(arguments: [(nil, 44), (22.0, 44), (18.0, 44), (24.0, 48), (30.0, 60)] as [(Double?, Int)])
    func pillIsAsTallAsItsHeight(height: Double?, pixels: Int) {
        let snapshot = Fixture.snapshot(plan: Fixture.plan(weekly: 89, fiveHour: 14), sessions: [Fixture.session("a", .working)])
        let pill = height.map { PillView(snapshot: snapshot, moment: nil, now: now, height: $0) }
            ?? PillView(snapshot: snapshot, moment: nil, now: now)
        #expect(render(pill)?.height == pixels)
    }

    @Test func momentWidensThePill() {
        let snapshot = Fixture.snapshot(sessions: [Fixture.session("a", .working)])
        let plain = render(PillView(snapshot: snapshot, moment: nil, now: now))
        let moment = render(PillView(snapshot: snapshot, moment: .sessionFinished(sessionID: "a", name: "Tidy build script"), now: now))
        #expect((moment?.width ?? 0) > (plain?.width ?? .max))
        #expect(moment?.height == 44)
    }

    @Test func panelIs360PointsWide() {
        let sessions = [Fixture.session("w", .working)] + (1...7).map { Fixture.session("i\($0)", .idle) }
        let image = render(PanelView(snapshot: Fixture.snapshot(sessions: sessions), now: now, actions: .none))
        #expect(image?.width == 720)
    }

    @Test func panelFitsAHeightCappedWindow() {
        // The app caps the panel window to the space below the menu bar. With many sessions the
        // panel must fit that height (the list scrolls) so the header and the gear menu stay visible.
        let sessions = (1...40).map { Fixture.session("w\($0)", .working) }
        let panel = PanelView(snapshot: Fixture.snapshot(sessions: sessions), now: now, actions: .none)

        let natural = ImageRenderer(content: panel)
        natural.scale = 1
        #expect((natural.cgImage?.height ?? 0) > 1000, "unconstrained, the panel still asks for its full height")

        let capped = ImageRenderer(content: panel)
        capped.scale = 1
        capped.proposedSize = ProposedViewSize(width: nil, height: 500)
        #expect(capped.cgImage?.height == 500)
        #expect(capped.cgImage?.width == 360)
    }

    @Test func panelRendersEveryState() {
        let states = [
            Fixture.snapshot(plan: .empty, issues: [.claudeCodeFolderUnavailable, .desktopFolderUnavailable]),
            Fixture.snapshot(plan: Fixture.plan(weekly: 89, fiveHour: 14, age: 42 * 60, extra: 12)),
            Fixture.snapshot(plan: .empty, issues: [.desktopUsageUnrecognized]),
        ]
        for snapshot in states {
            #expect(render(PanelView(snapshot: snapshot, now: now, actions: .none))?.width == 720)
        }
    }

    @Test func everySymbolExists() {
        let moments: [Moment] = [
            .sessionFinished(sessionID: "a", name: "x"),
            .sessionNeedsInput(sessionID: "a", name: "x"),
            .limitCrossed(kind: .weekly, percent: 90),
        ]
        let names = moments.compactMap { PillModel(snapshot: Fixture.snapshot(), moment: $0, now: now).moment?.symbol }
            + Symbols.all
        for name in names {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "missing SF Symbol \(name)")
        }
    }

    @Test func pulsePhaseCyclesEverySixteenHundredMilliseconds() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(PulsingDot.phase(at: start) == 0)
        #expect(abs(PulsingDot.phase(at: start.addingTimeInterval(0.8)) - 0.5) < 1e-9)
        #expect(abs(PulsingDot.phase(at: start.addingTimeInterval(1.6 + 0.4)) - 0.25) < 1e-9)
        #expect(PulsingDot.phase(at: Date(timeIntervalSinceReferenceDate: -0.4)) >= 0)
    }
}
