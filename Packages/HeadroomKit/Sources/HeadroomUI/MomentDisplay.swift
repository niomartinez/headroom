import HeadroomModel

/// The SF Symbol and short text the pill shows for a moment (spec §1.1, §3.4).
public struct MomentDisplay: Sendable, Equatable {
    public enum Tone: Sendable, Equatable {
        case finished
        case needsInput
        case limit(Severity)
    }

    public var symbol: String
    /// The whole text: "Tidy build script finished".
    public var text: String
    public var tone: Tone
    /// The session name `text` starts with, for session moments. The pill shortens only this part
    /// when the text is too wide, so the status after it stays readable. Nil: `text` is shown whole.
    public var name: String?

    public init(symbol: String, text: String, tone: Tone) {
        self.symbol = symbol
        self.text = text
        self.tone = tone
        spokenText = text
    }

    /// A session moment: `name` followed by `status` ("finished", "needs you").
    public init(symbol: String, name: String, status: String, tone: Tone) {
        self.init(symbol: symbol, text: "\(name) \(status)", tone: tone)
        self.name = name
    }

    /// `text` without the leading name: "finished", "needs you"; the whole text when there is no name.
    public var status: String {
        parts?.status ?? text
    }

    /// The name and the status after it, while `text` still starts with `name`.
    var parts: (name: String, status: String)? {
        guard let name, !name.isEmpty, text.hasPrefix(name) else { return nil }
        let rest = text.dropFirst(name.count)
        return (name, rest.trimmingCharacters(in: .whitespaces))
    }

    /// The whole text for VoiceOver: `text`, except that a session moment names its tool unless only Claude is
    /// tracked: "Codex session ledger finished" (1.1 §6.2).
    public var spokenText: String

    /// The moment as shown with only Claude tracked (1.0).
    public init(_ moment: Moment) {
        self.init(moment, trackedTools: [.claude])
    }

    /// The moment as shown with `trackedTools` tracked (1.1 §6.2): limit moments name their tool with two or more
    /// tools ("Codex weekly at 90%", "Claude 5-hour at 90%"); session moments never do on screen.
    public init(_ moment: Moment, trackedTools: [ToolID]) {
        let namesTool = trackedTools.count > 1
        switch moment {
        case .sessionFinished(let id, let name):
            self.init(symbol: "checkmark.circle.fill", name: name.nonBlank(or: "A session"), status: "finished", tone: .finished)
            speakTool(of: id, unless: trackedTools == [.claude])
        case .sessionNeedsInput(let id, let name):
            self.init(symbol: "exclamationmark.circle.fill", name: name.nonBlank(or: "A session"), status: "needs you", tone: .needsInput)
            speakTool(of: id, unless: trackedTools == [.claude])
        case .limitCrossed(let kind, let percent):
            let window: WindowKind = kind == .weekly ? .weekly : .fiveHour
            self.init(limitOf: .claude, window: window, percent: percent, namesTool: namesTool)
        case .toolLimitCrossed(let tool, let window, let percent):
            self.init(limitOf: tool, window: window, percent: percent, namesTool: namesTool)
        }
    }

    /// "Weekly at 90%" / "Weekly limit reached"; Copilot keeps working on paid extra usage, so its 100 % is "used
    /// up": "Monthly credits used up". Named: "Codex weekly at 90%", "Copilot credits used up".
    private init(limitOf tool: ToolID, window: WindowKind, percent: Int, namesTool: Bool) {
        let title = namesTool ? "\(tool.shortName) \(window.title.lowercased())" : window.title
        let text = switch (tool, percent >= 100) {
        case (_, false): "\(title) at \(percent)%"
        case (.copilot, true): namesTool ? "\(tool.shortName) credits used up" : "\(window.title) credits used up"
        case (_, true): "\(title) limit reached"
        }
        self.init(symbol: "gauge.with.needle", text: text, tone: .limit(Thresholds.limits.severity(for: Double(percent))))
    }

    private mutating func speakTool(of sessionID: String, unless claudeOnly: Bool) {
        guard !claudeOnly else { return }
        spokenText = "\(ToolID(sessionID: sessionID).shortName) session \(text)"
    }
}

extension LimitKind {
    /// "Weekly" / "5-hour".
    var title: String {
        switch self {
        case .weekly: "Weekly"
        case .fiveHour: "5-hour"
        }
    }
}
