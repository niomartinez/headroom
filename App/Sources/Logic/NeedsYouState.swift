import Foundation
import HeadroomModel
import HeadroomStore
import HeadroomUI

/// "Needs you" stays until seen (1.1 §14.4), the app's side. Holds `NeedsYouTracker` (which waits the user saw or
/// dismissed), saves its marks in UserDefaults so a relaunch doesn't nag, reads "Keep “needs you” in the menu bar
/// until I look", and remembers what the pill showed when the panel opened: the rest state stays until the panel
/// closes, then the pill narrows. `AppModel` feeds it every applied real snapshot; sample data never reaches it.
struct NeedsYouState {
    /// While the panel is open.
    struct Hold: Equatable {
        /// The pill's rest state when the panel opened: kept until it closes.
        var attention: NeedsYouAttention?
        /// Waits not seen before the panel opened, or that began while it was open: the panel's wash.
        var unseenIDs: Set<String>
    }

    private(set) var tracker: NeedsYouTracker
    /// "Keep “needs you” in the menu bar until I look".
    private(set) var keepsInMenuBar: Bool
    /// Non-nil while the panel is open.
    private(set) var hold: Hold?
    /// Where the marks are saved; nil for `--render-live`, which runs beside the menu bar app and must not write its
    /// settings.
    private let defaults: UserDefaults?

    /// Loads the saved marks and the setting (`Preferences.registerDefaults` must have run). `persists` false reads
    /// them but never writes.
    init(defaults: UserDefaults, persists: Bool = true) {
        tracker = NeedsYouTracker(
            seen: NeedsYouMarks.decode(defaults.array(forKey: Preferences.needsYouAcknowledged)),
            dismissed: NeedsYouMarks.decode(defaults.array(forKey: Preferences.needsYouDismissed))
        )
        keepsInMenuBar = defaults.bool(forKey: Preferences.keepNeedsYou)
        self.defaults = persists ? defaults : nil
    }

    /// A real snapshot was applied: episodes start and end, stale marks go. While the panel is open, every wait in it
    /// counts as seen (and new ones get the wash).
    mutating func update(sessions: [SessionInfo], now: Date) {
        changingMarks {
            $0.update(sessions: sessions, now: now)
        }
        if hold != nil {
            markAllSeen(now: now)
        }
    }

    /// The snapshot as the pill, panel, VoiceOver and widgets show it: dismissed waits read as idle. Sample data is
    /// shown as it is: the marks belong to real sessions.
    func presentation(of snapshot: HeadroomSnapshot, sampleData: Bool) -> NeedsYouPresentation {
        guard !sampleData else { return NeedsYouPresentation(snapshot: snapshot, dismissedIDs: [], unseen: []) }
        return tracker.presentation(of: snapshot)
    }

    /// The pill's rest state, "(!) harbor" or "(!) 2 need you": the unseen waits, while moments and the setting are
    /// on and sample data is off; while the panel is open, what it showed when the panel opened.
    func pillAttention(_ presentation: NeedsYouPresentation, showsMoments: Bool, sampleData: Bool) -> NeedsYouAttention? {
        guard keepsInMenuBar, showsMoments, !sampleData else { return nil }
        if let hold { return hold.attention }
        return NeedsYouAttention(names: presentation.unseenNames)
    }

    /// Unseen rows the open panel washes; none while it is closed.
    var panelUnseenIDs: Set<String> {
        hold?.unseenIDs ?? []
    }

    /// The panel opened: the pill keeps `attention` until it closes, and every wait counts as seen. Returns the
    /// sessions just seen, whose "needs you" moments no longer need to play. In sample data nothing is marked: the
    /// panel lists made-up sessions.
    mutating func panelOpened(attention: NeedsYouAttention?, sampleData: Bool, now: Date) -> Set<String> {
        hold = Hold(attention: attention, unseenIDs: [])
        guard !sampleData else { return [] }
        return markAllSeen(now: now)
    }

    /// The panel closed: the pill shows what is still unseen (usually nothing, so it narrows).
    mutating func panelClosed() {
        hold = nil
    }

    /// "Dismiss" on a Needs you row. Returns `true` when that changed anything.
    @discardableResult
    mutating func dismiss(_ id: String, now: Date) -> Bool {
        changingMarks { $0.dismiss(id, now: now) }
    }

    /// "Show in Needs you again". Returns `true` when that changed anything.
    @discardableResult
    mutating func undoDismiss(_ id: String) -> Bool {
        changingMarks { $0.undoDismiss(id) }
    }

    mutating func setKeepsInMenuBar(_ enabled: Bool) {
        keepsInMenuBar = enabled
        defaults?.set(enabled, forKey: Preferences.keepNeedsYou)
    }

    /// Marks every unseen wait seen, after adding it to the open panel's wash. Returns their ids.
    @discardableResult
    private mutating func markAllSeen(now: Date) -> Set<String> {
        let unseen = Set(tracker.episodes.keys.filter(tracker.isUnseen))
        guard !unseen.isEmpty else { return [] }
        hold?.unseenIDs.formUnion(unseen)
        changingMarks { $0.markAllSeen(now: now) }
        return unseen
    }

    /// Runs `change` and saves the marks when they changed (episodes are never saved). Returns whether they did.
    @discardableResult
    private mutating func changingMarks(_ change: (inout NeedsYouTracker) -> Void) -> Bool {
        let before = (tracker.seen, tracker.dismissed)
        change(&tracker)
        guard before != (tracker.seen, tracker.dismissed) else { return false }
        defaults?.set(NeedsYouMarks.encode(tracker.seen), forKey: Preferences.needsYouAcknowledged)
        defaults?.set(NeedsYouMarks.encode(tracker.dismissed), forKey: Preferences.needsYouDismissed)
        return true
    }
}

/// `NeedsYouTracker.Mark`s as UserDefaults stores them: an array of `{session, episodeStart, at}` dictionaries, the
/// dates in seconds since 1970. Only session ids and times; never names or paths.
enum NeedsYouMarks {
    private static let sessionKey = "session"
    private static let episodeStartKey = "episodeStart"
    private static let atKey = "at"

    static func encode(_ marks: [NeedsYouTracker.Mark]) -> [[String: Any]] {
        marks.map {
            [
                sessionKey: $0.sessionID,
                episodeStartKey: $0.episodeStart.timeIntervalSince1970,
                atKey: $0.at.timeIntervalSince1970,
            ]
        }
    }

    /// Entries that aren't well-formed are skipped; anything else (nil, another type) reads as no marks.
    static func decode(_ value: [Any]?) -> [NeedsYouTracker.Mark] {
        (value ?? []).compactMap { entry in
            guard let entry = entry as? [String: Any],
                  let id = entry[sessionKey] as? String, !id.isEmpty,
                  let start = (entry[episodeStartKey] as? NSNumber)?.doubleValue, start.isFinite,
                  let at = (entry[atKey] as? NSNumber)?.doubleValue, at.isFinite
            else { return nil }
            return NeedsYouTracker.Mark(
                sessionID: id,
                episodeStart: Date(timeIntervalSince1970: start),
                at: Date(timeIntervalSince1970: at)
            )
        }
    }
}
