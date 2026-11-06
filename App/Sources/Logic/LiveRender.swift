import CoreGraphics
import Foundation
import HeadroomModel

/// `Headroom --render-live <dir>`: renders what the app would show right now from real data, for
/// checking the running app by eye without screenshots (spec §5).
enum LiveRender {
    /// Long enough for two or three polls, so data settles and moments between polls are detected.
    static let settleDuration: Duration = .seconds(5)
    /// The process exits by itself even if rendering hangs.
    static let timeout: Duration = .seconds(30)
    static let scale: CGFloat = 2

    static let pillFile = "live-pill.png"
    /// Only written when a moment is showing or queued; removed otherwise so an old one can't mislead.
    static let momentPillFile = "live-pill-moment.png"
    static let panelFile = "live-panel.png"
    static let snapshotFile = "live-snapshot.json"

    /// The moment the pill is showing, or else the next one waiting.
    static func momentToRender(current: Moment?, pending: [Moment]) -> Moment? {
        current ?? pending.first
    }

    /// The snapshot as `headroom-dump` prints it: pretty-printed, sorted keys, ISO 8601 dates.
    static func snapshotJSON(_ snapshot: HeadroomSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }
}
