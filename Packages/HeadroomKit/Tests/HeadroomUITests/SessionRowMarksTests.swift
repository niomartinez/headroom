import Foundation
import HeadroomModel
import Testing
@testable import HeadroomUI

/// Session rows that open their session (1.1 §14.3) and the "needs you" marks: unseen, dismissed (1.1 §14.4).
@Suite struct SessionRowMarksTests {
    private let sessions = [
        Fixture.session("w1", .working, name: "Refactor invoice export", path: "/Users/me/code/ledger"),
        Fixture.session("t1", .waitingForInput, name: "harbor", origin: .terminal,
                        context: Fixture.context(130_000, of: 200_000, model: "test-model-large")),
        Fixture.session("t2", .waitingForInput, name: "atlas", origin: .terminal),
        Fixture.session("i1", .idle, name: "Sketch copy"),
    ]

    private func rows(_ model: PanelModel) -> [String: PanelModel.SessionRow] {
        Dictionary(uniqueKeysWithValues: model.sections.flatMap(\.rows).map { ($0.id, $0) })
    }

    @Test func openTitlesReachTheirRowsOnly() {
        let model = PanelModel(
            snapshot: Fixture.snapshot(sessions: sessions), now: Fixture.now,
            openTitles: ["w1": "Open in Claude", "t1": "Show in Terminal"]
        )
        let byID = rows(model)
        #expect(byID["w1"]?.openTitle == "Open in Claude")
        #expect(byID["t1"]?.openTitle == "Show in Terminal")
        #expect(byID["t2"]?.openTitle == nil)
        #expect(byID["i1"]?.openTitle == nil)
    }

    /// The tooltip leads with where the click goes, then the context help.
    @Test func tooltipJoinsTitleAndHelp() {
        let byID = rows(PanelModel(
            snapshot: Fixture.snapshot(sessions: sessions), now: Fixture.now,
            openTitles: ["t1": "Show in Terminal", "w1": "Open in Claude"]
        ))
        #expect(byID["t1"]?.tooltip == "Show in Terminal · 130k of 200k tokens · test-model-large")
        #expect(byID["w1"]?.tooltip == "Open in Claude")
        #expect(byID["i1"]?.tooltip == "")
    }

    /// Hidden idle rows get their titles too, once expanded.
    @Test func expandedIdleRowsKeepTheirTitles() {
        let idle = (1...5).map { Fixture.session("i\($0)", .idle) }
        let titles = Dictionary(uniqueKeysWithValues: idle.map { ($0.id, "Open in Claude") })
        let model = PanelModel(snapshot: Fixture.snapshot(sessions: idle), now: Fixture.now, idleExpanded: true, openTitles: titles)
        #expect(model.sections.flatMap(\.rows).allSatisfy { $0.openTitle == "Open in Claude" })
    }

    @Test func waitingRowsCanBeDismissedOutsideSampleData() {
        let real = rows(PanelModel(snapshot: Fixture.snapshot(sessions: sessions), now: Fixture.now))
        #expect(real.values.filter(\.canDismiss).map(\.id).sorted() == ["t1", "t2"])
        let sample = rows(PanelModel(snapshot: Fixture.snapshot(sessions: sessions), now: Fixture.now, sampleData: .showing))
        #expect(sample.values.allSatisfy { !$0.canDismiss })
    }

    /// 1.1.1: finished idle sessions get their own section between Needs you and Idle, can be dismissed and cleared.
    @Test func finishedSessionsAreListedInJustFinished() {
        let model = PanelModel(
            snapshot: Fixture.snapshot(sessions: sessions + [Fixture.session("i2", .idle, name: "Tidy CI")]),
            now: Fixture.now, finishedIDs: ["i1", "w1"]
        )
        #expect(model.sections.map(\.kind) == [.working, .needsYou, .justFinished, .idle])
        let finished = model.sections.first { $0.kind == .justFinished }
        #expect(finished?.title == "Just finished")
        #expect(finished?.rows.map(\.id) == ["i1"])
        #expect(finished?.clearTitle == "Clear")
        #expect(finished?.rows.first?.attention == .finished)
        #expect(finished?.rows.first?.canDismiss == true)
        #expect(finished?.rows.first?.accessibilityLabel.hasSuffix("idle, finished") == true)
        #expect(model.sections.first { $0.kind == .idle }?.rows.map(\.id) == ["i2"])
        // A working session marked finished stays in Working.
        #expect(model.sections.first { $0.kind == .working }?.rows.map(\.id) == ["w1"])
    }

    @Test func sampleDataCannotClearOrDismissFinishedRows() {
        let model = PanelModel(
            snapshot: Fixture.snapshot(sessions: sessions), now: Fixture.now, sampleData: .showing, finishedIDs: ["i1"]
        )
        let finished = model.sections.first { $0.kind == .justFinished }
        #expect(finished?.clearTitle == nil)
        #expect(finished?.rows.first?.canDismiss == false)
    }

    @Test func unseenWaitingRowsAreMarked() {
        let byID = rows(PanelModel(
            snapshot: Fixture.snapshot(sessions: sessions), now: Fixture.now, unseenIDs: ["t2", "w1"]
        ))
        #expect(byID["t2"]?.attention == .unseen)
        #expect(byID["t1"]?.attention == PanelModel.RowAttention.none)
        // Only waiting rows can be unseen.
        #expect(byID["w1"]?.attention == PanelModel.RowAttention.none)
        #expect(byID["t2"]?.accessibilityLabel == "atlas, terminal, needs input, new")
    }

    /// A dismissed wait is listed last in Needs you, whether the snapshot still says waiting or already reads it as
    /// idle (the presentation the app shows).
    @Test(arguments: [SessionActivity.waitingForInput, .idle])
    func dismissedRowsComeLastInNeedsYou(shownAs activity: SessionActivity) {
        var shown = sessions
        shown[1].activity = activity
        let model = PanelModel(
            snapshot: Fixture.snapshot(sessions: shown.sortedForDisplay()), now: Fixture.now, dismissedIDs: ["t1"]
        )
        let needsYou = model.sections.first { $0.kind == .needsYou }
        #expect(needsYou?.rows.map(\.id) == ["t2", "t1"])
        #expect(model.sections.first { $0.kind == .idle }?.rows.map(\.id) == ["i1"])

        let dismissed = try? #require(needsYou?.rows.last)
        #expect(dismissed?.attention == .dismissed)
        #expect(dismissed?.dot == .waiting)
        #expect(dismissed?.canDismiss == false)
        #expect(dismissed?.helpText == "Dismissed · still waiting · 130k of 200k tokens · test-model-large")
        #expect(dismissed?.accessibilityLabel == "harbor, terminal, needs input, dismissed")
    }

    @Test func aDismissedIDThatWentBackToWorkIsAWorkingRow() {
        let model = PanelModel(snapshot: Fixture.snapshot(sessions: sessions), now: Fixture.now, dismissedIDs: ["w1"])
        #expect(model.sections.first { $0.kind == .working }?.rows.map(\.id) == ["w1"])
        #expect(rows(model)["w1"]?.attention == PanelModel.RowAttention.none)
    }

    @Test func dismissedHelpWithoutContext() {
        let byID = rows(PanelModel(snapshot: Fixture.snapshot(sessions: sessions), now: Fixture.now, dismissedIDs: ["t2"]))
        #expect(byID["t2"]?.helpText == "Dismissed · still waiting")
    }
}
