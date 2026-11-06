import Foundation

/// Orders overlapping polls (spec §4). `AppModel.refresh()` runs from the poll loop and, at the
/// same time, after a grant or a Connect; a poll that finishes after a newer one was applied must
/// not overwrite it.
///
/// Polls are ordered by a counter, not by their wall-clock start: the system clock can step back
/// (set by hand, or corrected after sleep), and comparing dates would then drop every poll until
/// the clock caught up, freezing the pill and panel.
struct PollOrdering {
    struct Poll: Equatable {
        /// The wall-clock time the poll started; the snapshot is built for this "now".
        let startedAt: Date
        fileprivate let sequence: Int
    }

    private var issued = 0
    private var applied = 0

    mutating func begin(at date: Date = Date()) -> Poll {
        issued += 1
        return Poll(startedAt: date, sequence: issued)
    }

    /// `true` when `poll` is newer than every poll applied so far; it then becomes the newest.
    mutating func shouldApply(_ poll: Poll) -> Bool {
        guard poll.sequence > applied else { return false }
        applied = poll.sequence
        return true
    }
}
