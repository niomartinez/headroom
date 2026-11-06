import Foundation

/// Waiting sessions the user hasn't seen yet (1.1 §14.4): the pill's rest state after the 4 s "harbor needs you"
/// moment, "(!) harbor" or "(!) 2 need you", until the panel is opened, the session stops waiting or it is
/// dismissed. The app builds it from `NeedsYouTracker`'s unseen sessions; never in sample data, nor with "Keep
/// “needs you” in the menu bar until I look" off.
public struct NeedsYouAttention: Sendable, Equatable {
    /// The unseen sessions' names, in display order (most recently waiting first).
    public var names: [String]

    /// Nil when nobody is waiting unseen.
    public init?(names: [String]) {
        guard !names.isEmpty else { return nil }
        self.names = names
    }

    /// One session: its name ("harbor"; "A session" when it has none). The rest state never names the tool
    /// (1.1 §6.2).
    public var name: String? {
        names.count == 1 ? names[0].nonBlank(or: "A session") : nil
    }

    /// Two or more: "2 need you".
    public var status: String? {
        names.count == 1 ? nil : "\(names.count) need you"
    }

    /// What the pill shows after the symbol.
    public var text: String {
        name ?? status ?? ""
    }

    /// VoiceOver, first in the status item's label: "harbor needs your input", "2 sessions need your input: harbor,
    /// atlas".
    public var spoken: String {
        let shown = names.map { $0.nonBlank(or: "A session") }
        return shown.count == 1
            ? "\(shown[0]) needs your input"
            : "\(shown.count) sessions need your input: \(shown.joined(separator: ", "))"
    }
}
