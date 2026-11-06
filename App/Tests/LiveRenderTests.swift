import Foundation
import HeadroomModel
import Testing

@Suite struct LiveRenderTests {
    @Test func outputFileNames() {
        #expect(LiveRender.pillFile == "live-pill.png")
        #expect(LiveRender.momentPillFile == "live-pill-moment.png")
        #expect(LiveRender.panelFile == "live-panel.png")
        #expect(LiveRender.snapshotFile == "live-snapshot.json")
    }

    @Test func rendersAtTwiceTheScaleAfterAboutFiveSeconds() {
        #expect(LiveRender.scale == 2)
        #expect(LiveRender.settleDuration == .seconds(5))
        #expect(LiveRender.timeout > LiveRender.settleDuration)
    }

    @Test func theShowingMomentIsRendered() {
        let showing = Moment.sessionNeedsInput(sessionID: "a", name: "Alpha")
        let queued = Moment.limitCrossed(kind: .weekly, percent: 90)
        #expect(LiveRender.momentToRender(current: showing, pending: [queued]) == showing)
    }

    @Test func aQueuedMomentIsRenderedWhenNoneIsShowing() {
        let queued = Moment.limitCrossed(kind: .weekly, percent: 90)
        #expect(LiveRender.momentToRender(current: nil, pending: [queued]) == queued)
        #expect(LiveRender.momentToRender(current: nil, pending: []) == nil)
    }

    @Test func snapshotJSONRoundTrips() throws {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = HeadroomSnapshot(
            plan: PlanUsage(weekly: LimitReading(
                kind: .weekly, usedPercent: 42, resetsAt: at.addingTimeInterval(86_400), resetIsEstimated: true,
                observedAt: at.addingTimeInterval(-120), source: .desktopApp
            )),
            sessions: [],
            terminalBridgeConnected: false,
            issues: [.desktopUsageUnrecognized],
            generatedAt: at
        )
        let data = try LiveRender.snapshotJSON(snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(HeadroomSnapshot.self, from: data) == snapshot)

        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"generatedAt\" : \"2027-01-15T08:00:00Z\""))
        // Sorted keys, pretty-printed: stable output to diff between runs.
        let generated = try #require(text.range(of: "\"generatedAt\""))
        let plan = try #require(text.range(of: "\"plan\""))
        #expect(generated.lowerBound < plan.lowerBound)
    }
}
