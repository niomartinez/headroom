import CoreGraphics
import Foundation
import HeadroomModel
import HeadroomUI

/// Remembers the last value a view was handed, so it only gets new content when that content
/// changed. The poll produces a new snapshot every 2 s (a new `generatedAt`, a new "now") even when
/// nothing on screen would change; handing it over anyway re-renders the status item for nothing.
struct ChangeGate<Value: Equatable> {
    private(set) var last: Value?

    /// `true` when `value` differs from the last admitted value (always for the first one); the
    /// value is then remembered.
    mutating func admit(_ value: Value) -> Bool {
        guard value != last else { return false }
        last = value
        return true
    }

    mutating func reset() {
        last = nil
    }
}

/// Everything one menu bar pill is drawn from (`PillView`'s arguments, 1.1 §6.1, §14.4, §14.6): what the status item
/// hands `PillMotion`, and what its draw key is built from.
struct PillInputs: Equatable, Sendable {
    /// Waiting already has a persistent title. A second, temporary "needs you" layout only makes that title
    /// and its trailing gauges rearrange again when the announcement timer expires.
    static func menuBarMoment(_ moment: Moment?) -> Moment? {
        if case .sessionNeedsInput = moment { return nil }
        return moment
    }

    var snapshot: HeadroomSnapshot
    var moment: Moment?
    var now: Date
    /// "Rings show" (nil = Automatic).
    var tool: ToolID? = nil
    /// "One gauge per tool".
    var gaugePerTool = false
    /// The needs-you rest state.
    var attention: NeedsYouAttention? = nil
    /// Waits the user dismissed: they leave the dot and the count.
    var dismissedIDs: Set<String> = []
    /// The pill's height, from the menu bar's.
    var height: CGFloat = PillMetrics.minimumHeight
    /// The native menu-bar space available to the entire image, including gauges and padding.
    var maximumWidth: CGFloat? = nil
    var compact = false

    var completionID: String? {
        if case .sessionFinished(let id, _) = moment { return id }
        return nil
    }

    var model: PillModel {
        PillModel(
            snapshot: snapshot, moment: moment, now: now, tool: tool, gaugePerTool: gaugePerTool && !compact, attention: attention,
            dismissedIDs: dismissedIDs, height: height
        )
    }
}

/// What the menu bar pill draws for a snapshot: equal keys draw the same pill. The model is built with "Rings show"
/// (`tool`, nil = Automatic), "One gauge per tool", the needs-you rest state, the dismissed waits and the pill's height,
/// so changing any of them redraws (1.1 §6.1, §14.4, §14.6).
struct PillDrawKey: Equatable {
    let model: PillModel
    /// The moment itself, not just its display: a second moment with the same text is still a new
    /// event to announce.
    let moment: Moment?
    let maximumWidth: CGFloat?
    let compact: Bool

    init(_ inputs: PillInputs) {
        model = inputs.model
        moment = inputs.moment
        maximumWidth = inputs.maximumWidth
        compact = inputs.compact
    }

    init(
        snapshot: HeadroomSnapshot, moment: Moment?, now: Date, tool: ToolID? = nil, gaugePerTool: Bool = false,
        attention: NeedsYouAttention? = nil, dismissedIDs: Set<String> = [], height: CGFloat = PillMetrics.minimumHeight
    ) {
        self.init(PillInputs(
            snapshot: snapshot, moment: moment, now: now, tool: tool, gaugePerTool: gaugePerTool, attention: attention,
            dismissedIDs: dismissedIDs, height: height
        ))
    }
}

/// What the panel draws for a snapshot: equal keys draw the same panel. Built with "Rings show" (the header's tool),
/// the Codex offer, the needs-you marks and where each row opens, so changing any of them redraws (1.1 §6.3, §14.3,
/// §14.4).
struct PanelDrawKey: Equatable {
    /// Built expanded, so idle rows behind "Show N more" count too: the user can expand them.
    let model: PanelModel

    init(
        snapshot: HeadroomSnapshot, now: Date, sampleData: PanelSampleData = .hidden, tool: ToolID? = nil,
        showsCodexOffer: Bool = false, unseenIDs: Set<String> = [], dismissedIDs: Set<String> = [],
        finishedIDs: Set<String> = [], openTitles: [String: String] = [:]
    ) {
        model = PanelModel(
            snapshot: snapshot, now: now, idleExpanded: true, sampleData: sampleData, tool: tool,
            showsCodexOffer: showsCodexOffer, unseenIDs: unseenIDs, dismissedIDs: dismissedIDs, finishedIDs: finishedIDs,
            openTitles: openTitles
        )
    }
}
