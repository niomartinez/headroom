import CoreGraphics
import Testing

@Suite struct PanelPlacementTests {
    /// A 1440×900 screen with a 24 pt menu bar: visible frame ends at the menu bar's bottom edge.
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 876)
    private let gap = PanelPlacement.gap
    private let margin = PanelPlacement.margin

    @Test func rightAlignsUnderTheStatusItem() {
        let anchor = CGRect(x: 1100, y: 876, width: 80, height: 24)
        let frame = PanelPlacement.frame(contentSize: CGSize(width: 360, height: 300), below: anchor, in: visible)
        #expect(frame.maxX == anchor.maxX)
        #expect(frame.maxY == anchor.minY - gap)
        #expect(frame.size == CGSize(width: 360, height: 300))
    }

    @Test func clampsToTheLeftEdgeOfTheScreen() {
        let anchor = CGRect(x: 40, y: 876, width: 80, height: 24)
        let frame = PanelPlacement.frame(contentSize: CGSize(width: 360, height: 300), below: anchor, in: visible)
        #expect(frame.minX == visible.minX + margin)
        #expect(frame.width == 360)
    }

    @Test func clampsToTheRightEdgeOfTheScreen() {
        let anchor = CGRect(x: 1400, y: 876, width: 60, height: 24)
        let frame = PanelPlacement.frame(contentSize: CGSize(width: 360, height: 300), below: anchor, in: visible)
        #expect(frame.maxX == visible.maxX - margin)
    }

    @Test func capsHeightToTheSpaceBelowTheMenuBar() {
        let anchor = CGRect(x: 1100, y: 876, width: 80, height: 24)
        let frame = PanelPlacement.frame(contentSize: CGSize(width: 360, height: 5000), below: anchor, in: visible)
        #expect(frame.minY == visible.minY + margin)
        #expect(frame.maxY == anchor.minY - gap)
    }

    @Test func capsWidthOnANarrowScreen() {
        let narrow = CGRect(x: 0, y: 0, width: 300, height: 876)
        let anchor = CGRect(x: 200, y: 876, width: 80, height: 24)
        let frame = PanelPlacement.frame(contentSize: CGSize(width: 360, height: 200), below: anchor, in: narrow)
        #expect(frame.minX == narrow.minX + margin)
        #expect(frame.maxX == narrow.maxX - margin)
    }

    @Test func staysBelowTheVisibleFrameWhenTheMenuBarOverlapsIt() {
        // Auto-hidden menu bar: the visible frame reaches the top of the screen, under the status item.
        let full = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = CGRect(x: 1100, y: 876, width: 80, height: 24)
        let frame = PanelPlacement.frame(contentSize: CGSize(width: 360, height: 300), below: anchor, in: full)
        #expect(frame.maxY == anchor.minY - gap)
    }

    @Test func worksOnASecondaryScreenWithOffsetOrigin() {
        let secondary = CGRect(x: -1920, y: 200, width: 1920, height: 1056)
        let anchor = CGRect(x: -300, y: 1256, width: 70, height: 24)
        let frame = PanelPlacement.frame(contentSize: CGSize(width: 360, height: 400), below: anchor, in: secondary)
        #expect(frame.maxX == anchor.maxX)
        #expect(frame.maxY == anchor.minY - gap)
        #expect(secondary.contains(frame))
    }

    @Test func producesWholePointOrigins() {
        let anchor = CGRect(x: 1100.4, y: 876, width: 80.3, height: 24)
        let frame = PanelPlacement.frame(contentSize: CGSize(width: 360, height: 301.6), below: anchor, in: visible)
        #expect(frame.minX == frame.minX.rounded())
        #expect(frame.minY == frame.minY.rounded())
    }

    @Test func degenerateInputsNeverProduceNegativeSizes() {
        let tiny = CGRect(x: 0, y: 0, width: 10, height: 10)
        let anchor = CGRect(x: 0, y: 10, width: 20, height: 24)
        let frame = PanelPlacement.frame(contentSize: CGSize(width: 360, height: 300), below: anchor, in: tiny)
        #expect(frame.width >= 0)
        #expect(frame.height >= 0)
    }
}
