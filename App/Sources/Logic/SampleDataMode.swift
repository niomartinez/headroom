import Foundation
import HeadroomModel
import HeadroomUI

/// Sample data mode: made-up sessions and limits (`SampleData.showcase`) in place of real ones, for
/// App Review, demos, and anyone without Claude data on their Mac. Turned on in Settings ("Show
/// sample data") or from the empty panel ("Preview with sample data"); remembered across launches.
///
/// While it's on, the 2 s poll reads no real files and no moments are shown. Explicit actions (a
/// folder grant, Connect terminal) still check the real folders, so Settings stays true, and so
/// does one check on the first tick when the app launches with sample data on (nothing real has
/// been read then). What those checks read is never shown.
struct SampleDataMode: Equatable {
    enum PollSource: Equatable {
        /// Read `~/.claude` and the Claude app's folder, as always.
        case realFiles
        /// Make a sample snapshot for the current time; touch no files.
        case sample
        /// Sample data is on but nothing real has been checked since launch: check the real folders
        /// and the terminal bridge once, for Settings' rows and the panel's Connect / Disconnect
        /// terminal item, then make the sample snapshot. The snapshot the check builds isn't shown.
        case checkRealStateThenSample
    }

    /// What the model has to do after a switch.
    struct Switch: Equatable {
        /// Drop the moment on screen and the queued ones: moments are about real sessions and limits.
        var clearMoments: Bool
        /// Forget the last real snapshot as the moments' baseline, so the first real poll after sample
        /// data doesn't announce everything that changed while it showed.
        var resetMomentBaseline: Bool
        /// Show the new source at once instead of on the next 2 s tick.
        var pollNow: Bool
    }

    private(set) var isOn: Bool
    /// Bumped on every switch. A real poll that started under another epoch finished too late:
    /// its snapshot isn't shown (see `showsRealSnapshot(fromPollStartedIn:)`).
    private(set) var epoch = 0
    /// A real check (a poll, a grant, Connect terminal) has been applied since launch, so the
    /// access and terminal bridge state Settings shows is known.
    private(set) var hasCheckedRealState = false

    init(isOn: Bool) {
        self.isOn = isOn
    }

    var pollSource: PollSource {
        guard isOn else { return .realFiles }
        return hasCheckedRealState ? .sample : .checkRealStateThenSample
    }

    /// Called once a real check's access and bridge state were applied. A check that was dropped
    /// (out of date) doesn't count, so the next tick asks again.
    mutating func recordRealCheck() {
        hasCheckedRealState = true
    }

    /// Moments only come from real data, and only when the user wants them.
    func showsMoments(userSetting: Bool) -> Bool {
        userSetting && !isOn
    }

    /// Turns the mode on or off; nil when it already was.
    mutating func set(_ on: Bool) -> Switch? {
        guard on != isOn else { return nil }
        isOn = on
        epoch += 1
        return Switch(clearMoments: true, resetMomentBaseline: true, pollNow: true)
    }

    /// Whether a real poll that started in `epoch` may replace what the pill and panel show.
    func showsRealSnapshot(fromPollStartedIn epoch: Int) -> Bool {
        !isOn && epoch == self.epoch
    }

    /// What the panel shows about sample data. `lastReal` is the last real snapshot (nil before
    /// the first poll finished, so the offer doesn't flash at launch).
    func panelState(lastReal: HeadroomSnapshot?, access: AccessState) -> PanelSampleData {
        if isOn { return .showing }
        guard let lastReal, Self.foundNoClaudeData(lastReal, access: access) else { return .hidden }
        return .offered
    }

    /// No data at all: neither Claude folder readable, nor Codex's, no sessions and no usage from any tool. The case
    /// of a Mac without Claude Code or the Claude app (App Review), or before any folder was granted.
    static func foundNoClaudeData(_ snapshot: HeadroomSnapshot, access: AccessState) -> Bool {
        !access.claudeDirectoryReadable && !access.desktopDirectoryReadable && !access.codexDirectoryReadable
            && snapshot.sessions.isEmpty && snapshot.plan.isEmpty
            && (snapshot.codex?.limits.isEmpty ?? true) && (snapshot.copilot?.limits.isEmpty ?? true)
    }
}
