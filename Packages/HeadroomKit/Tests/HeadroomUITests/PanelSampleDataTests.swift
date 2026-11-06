import Foundation
import HeadroomModel
import SwiftUI
import Testing
@testable import HeadroomUI

/// Sample data mode in the panel: the offer in the empty state and the "Sample data · Turn off" footer.
@Suite struct PanelSampleDataTests {
    let now = Fixture.now

    private func model(_ snapshot: HeadroomSnapshot, _ sampleData: PanelSampleData) -> PanelModel {
        PanelModel(snapshot: snapshot, now: now, sampleData: sampleData, format: Fixture.format)
    }

    @Test func realDataShowsNeitherOfferNorTurnOff() {
        let panel = model(Fixture.snapshot(sessions: [Fixture.session("w", .working)]), .hidden)
        #expect(panel.sampleDataOffer == nil)
        #expect(panel.sampleDataTurnOff == nil)
        #expect(panel.footer.hasPrefix("Updated"))
    }

    @Test func theEmptyStateOffersAPreview() {
        let panel = model(Fixture.snapshot(plan: .empty), .offered)
        #expect(panel.emptyMessage == "No Claude Code sessions running")
        #expect(panel.sampleDataOffer == "Preview with sample data")
        #expect(panel.sampleDataTurnOff == nil)
        #expect(panel.footer == "No usage data yet")
    }

    @Test func showingSampleDataSaysSoInTheFooter() {
        let panel = model(Fixture.snapshot(sessions: [Fixture.session("w", .working)]), .showing)
        #expect(panel.footer == "Sample data")
        #expect(panel.sampleDataTurnOff == "Turn off")
        #expect(panel.sampleDataOffer == nil)
    }

    @Test func theDefaultIsRealData() {
        let snapshot = Fixture.snapshot()
        #expect(PanelModel(snapshot: snapshot, now: now, format: Fixture.format) == model(snapshot, .hidden))
    }

    @MainActor @Test func everySampleStateRenders() {
        for state in [PanelSampleData.hidden, .offered, .showing] {
            let renderer = ImageRenderer(content: PanelView(snapshot: Fixture.snapshot(plan: .empty), now: now, actions: .none, sampleData: state))
            renderer.scale = 2
            #expect(renderer.cgImage?.width == 720, "\(state)")
        }
    }
}
