import AppKit
import HeadroomModel
import HeadroomUI
import SwiftUI

/// PanelView for one snapshot. `PanelController` hands it a new snapshot only while the panel is
/// open and only when what the panel draws changed (`PanelDrawKey`).
struct PanelHost: View {
    let snapshot: HeadroomSnapshot
    let now: Date
    let actions: PanelActions
    var sampleData: PanelSampleData = .hidden
    /// "Rings show" (nil = Automatic): the header's tool (1.1 §6.3).
    var tool: ToolID? = nil
    var showsCodexOffer = false
    /// Waits not seen before the panel opened: a wash (1.1 §14.4).
    var unseenIDs: Set<String> = []
    /// Dismissed waits: last in Needs you, muted.
    var dismissedIDs: Set<String> = []
    /// Finished, not yet reviewed: Just finished (1.1.1).
    var finishedIDs: Set<String> = []
    /// Where each row opens (1.1 §14.3), as `actions.sessionOpenTitle` gave them when this was built: part of the draw
    /// key, so a row whose app changed is redrawn. `PanelView` asks the actions again (the opener caches them).
    var openTitles: [String: String] = [:]
    var keyboardNavigation = false

    var body: some View {
        PanelView(
            snapshot: snapshot, now: now, actions: actions, sampleData: sampleData, tool: tool,
            showsCodexOffer: showsCodexOffer, unseenIDs: unseenIDs, dismissedIDs: dismissedIDs, finishedIDs: finishedIDs
        )
        .environment(\.panelKeyboardNavigation, keyboardNavigation)
    }
}

/// Reports when the panel's content wants a different size (new sessions, "Show N more", …).
final class PanelHostingView: NSHostingView<PanelHost> {
    var onIntrinsicSizeChange: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onIntrinsicSizeChange?()
    }
}
