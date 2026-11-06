import CoreGraphics

/// Where the dropdown panel goes: right-aligned under the status item, inside the screen's
/// visible frame (spec §1.2). Screen coordinates, origin bottom-left.
enum PanelPlacement {
    /// Space between the menu bar and the panel's top edge.
    static let gap: CGFloat = 6
    /// Minimum distance from the visible frame's edges.
    static let margin: CGFloat = 8

    static func frame(contentSize: CGSize, below anchor: CGRect, in visibleFrame: CGRect) -> CGRect {
        let width = max(0, min(contentSize.width, visibleFrame.width - 2 * margin))
        let top = min(anchor.minY, visibleFrame.maxY) - gap
        let height = max(0, min(contentSize.height, top - (visibleFrame.minY + margin)))

        let minX = visibleFrame.minX + margin
        let maxX = max(minX, visibleFrame.maxX - margin - width)
        let x = min(max(anchor.maxX - width, minX), maxX)

        return CGRect(x: x.rounded(), y: (top - height).rounded(), width: width, height: height)
    }
}
