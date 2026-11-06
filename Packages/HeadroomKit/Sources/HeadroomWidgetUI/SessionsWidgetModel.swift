import Foundation
import HeadroomModel
import HeadroomShare
import HeadroomUI

/// What the Sessions widget shows at one timeline date (1.1 §5.6). Pure: no SwiftUI, no files.
public struct SessionsWidgetModel: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public var id: String
        /// The session's name, or the tool's ("Codex session") when names are hidden.
        public var name: String
        /// "Claude", "Codex", "Copilot" when the sessions mix tools (and names are shown), else nil.
        public var toolTag: String?
        public var isTerminal: Bool
        public var dot: DotState
        public var context: ContextBadge?

        public init(id: String, name: String, toolTag: String?, isTerminal: Bool, dot: DotState, context: ContextBadge?) {
            self.id = id
            self.name = name
            self.toolTag = toolTag
            self.isTerminal = isTerminal
            self.dot = dot
            self.context = context
        }

        /// "harbor, Codex, terminal, needs input, context 65% full".
        var accessibilityText: String {
            let context = context.map { $0.windowIsAssumed ? "context \($0.text) tokens" : "context \($0.text) full" }
            let state = switch dot {
            case .working: "working"
            case .waiting: "needs input"
            case .idle: "idle"
            }
            return [name, toolTag, isTerminal ? "terminal" : nil, state, context]
                .compactMap { $0 }
                .joined(separator: ", ")
        }
    }

    public struct Section: Sendable, Equatable, Identifiable {
        /// "Working", "Needs you", "Idle".
        public var title: String
        public var rows: [Row]

        public var id: String { title }
    }

    /// The most sessions the large widget lists.
    public static let largeRowLimit = 6
    /// The most sessions the medium widget lists.
    public static let mediumRowLimit = 3

    /// "2 working · 1 needs you", "3 idle", or "Sessions" when there are none (the body says so).
    public var headline: String
    public var dot: DotState
    /// Every session in the file, in display order (working, needs you, idle).
    public var rows: [Row]
    /// Compact rows for the tracked tools' limits (the large widget).
    public var tools: [WidgetToolSummary]
    /// "No sessions running" when there are none; nil without a file (the footer says "Open Headroom").
    public var emptyMessage: String?
    public var footer: WidgetFooter
    /// No file (or an unknown version).
    public var isEmpty: Bool
    /// Headroom stopped writing over 35 minutes ago: the sessions are old news and drawn dimmed.
    public var isOutdated: Bool

    public init(file: WidgetSnapshotFile?, now: Date, format: HeadroomFormat = HeadroomFormat()) {
        footer = WidgetFooter(file: file, now: now, format: format)
        guard let file else {
            headline = "Sessions"
            dot = .idle
            rows = []
            tools = []
            emptyMessage = nil
            isEmpty = true
            isOutdated = false
            return
        }
        let snapshot = file.snapshot.rolledOver(now: now)
        let sessions = snapshot.sessions
        let mixesTools = Set(sessions.map(\.tool)).count > 1
        rows = sessions.map { Self.row($0, tagged: mixesTools && file.showsSessionNames, format: format) }
        tools = ToolID.allCases.compactMap { WidgetToolSummary(tool: $0, snapshot: snapshot, now: now, format: format) }
        headline = Self.headline(sessions)
        dot = DotState(sessions: sessions)
        emptyMessage = sessions.isEmpty ? "No sessions running" : nil
        isEmpty = false
        isOutdated = !file.isHeadroomRunning(at: now)
    }

    /// The first `limit` rows, grouped Working / Needs you / Idle; empty groups are left out.
    public func sections(limit: Int) -> [Section] {
        let shown = Array(rows.prefix(max(0, limit)))
        return [(DotState.working, "Working"), (.waiting, "Needs you"), (.idle, "Idle")].compactMap { dot, title in
            let rows = shown.filter { $0.dot == dot }
            return rows.isEmpty ? nil : Section(title: title, rows: rows)
        }
    }

    /// "2 working · 1 needs you" (VoiceOver reads it as written).
    public var accessibilityLabel: String {
        ([headline] + rows.prefix(Self.largeRowLimit).map(\.accessibilityText) + [footer.text]).joined(separator: ". ")
    }

    private static func headline(_ sessions: [SessionInfo]) -> String {
        let working = sessions.filter { $0.activity == .working }.count
        let waiting = sessions.filter { $0.activity == .waitingForInput }.count
        var parts: [String] = []
        if working > 0 { parts.append("\(working) working") }
        if waiting > 0 { parts.append("\(waiting) \(waiting == 1 ? "needs" : "need") you") }
        if parts.isEmpty {
            let idle = sessions.count
            return idle > 0 ? "\(idle) idle" : "Sessions"
        }
        return parts.joined(separator: " · ")
    }

    private static func row(_ session: SessionInfo, tagged: Bool, format: HeadroomFormat) -> Row {
        let trimmed = session.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Row(
            id: session.id,
            name: trimmed.isEmpty ? "\(session.tool.shortName) session" : trimmed,
            toolTag: tagged ? session.tool.shortName : nil,
            isTerminal: session.origin == .terminal,
            dot: DotState(session.activity),
            context: session.context.flatMap { context(for: $0, format: format) }
        )
    }

    /// The panel's context badge (spec §1.2): a percent of a known window, or the token count when the window is
    /// only a guess.
    private static func context(for usage: ContextUsage, format: HeadroomFormat) -> ContextBadge? {
        if usage.windowIsAssumed {
            return ContextBadge(fraction: 0, text: format.tokenCount(usage.usedTokens), severity: .normal, windowIsAssumed: true)
        }
        guard usage.windowTokens > 0, let badge = PercentBadge(percent: usage.percent, thresholds: .context) else { return nil }
        return ContextBadge(fraction: min(1, max(0, usage.percent / 100)), text: badge.text, severity: badge.severity)
    }
}
