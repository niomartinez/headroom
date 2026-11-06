import Foundation
import HeadroomModel
import HeadroomShare
import HeadroomUI

/// What the Limits widget shows at one timeline date (1.1 §5.6). Pure: no SwiftUI, no files.
public struct LimitsWidgetModel: Sendable, Equatable {
    /// The one tool a small widget, or a medium one without columns, shows: the widget's choice, or for Automatic
    /// the tool the menu bar rings show. Its gauge is only tracks when there is no file or the tool isn't tracked.
    public var tool: WidgetToolSummary
    /// Automatic on a medium widget with two or more tools that have limits: one column each, in the fixed order
    /// (at most 3). Empty otherwise.
    public var columns: [WidgetToolSummary]
    /// The dot and count cover the sessions of every tracked tool, as in the pill.
    public var dot: DotState
    /// Working + waiting sessions; nil when 0.
    public var count: Int?
    public var footer: WidgetFooter
    /// No file (or an unknown version): empty tracks and "Open Headroom".
    public var isEmpty: Bool

    public init(file: WidgetSnapshotFile?, choice: WidgetToolChoice, now: Date, format: HeadroomFormat = HeadroomFormat()) {
        footer = WidgetFooter(file: file, now: now, format: format)
        guard let file else {
            tool = .placeholder(choice.tool ?? .claude)
            columns = []
            dot = .idle
            count = nil
            isEmpty = true
            return
        }
        let snapshot = file.snapshot.rolledOver(now: now)
        let summaries = ToolID.allCases.compactMap { WidgetToolSummary(tool: $0, snapshot: snapshot, now: now, format: format) }

        if let chosen = choice.tool {
            // Copilot tracked for its CLI sessions only has no usage to show.
            let status = snapshot.usage(for: chosen)?.status == .sessionsOnly ? "Sessions only" : "Not tracked"
            tool = summaries.first { $0.tool == chosen } ?? .placeholder(chosen, status: status)
        } else {
            tool = Self.automatic(summaries, pillTool: file.pillTool, snapshot: snapshot) ?? .placeholder(.claude)
        }
        columns = choice == .automatic && summaries.count >= 2 ? Array(summaries.prefix(3)) : []
        dot = DotState(sessions: snapshot.sessions)
        count = snapshot.activeCount > 0 ? snapshot.activeCount : nil
        isEmpty = false
    }

    /// The app's resolved "Rings show" tool when it is still tracked; else the rule the app uses (§6.1): the first
    /// tracked tool, Claude → Codex → Copilot, that has a limit with a percent, else the first tracked one.
    private static func automatic(
        _ summaries: [WidgetToolSummary], pillTool: ToolID?, snapshot: HeadroomSnapshot
    ) -> WidgetToolSummary? {
        if let pillTool, let summary = summaries.first(where: { $0.tool == pillTool }) { return summary }
        let withPercent = summaries.first { summary in
            snapshot.usage(for: summary.tool)?.limits.contains { $0.usedPercent != nil } ?? false
        }
        return withPercent ?? summaries.first
    }

    /// "Claude, 3 active sessions. Weekly, 89% used, resets Sun 7 PM. 5-hour, 14% used, resets in 2h 50m." —
    /// VoiceOver for the whole widget.
    public var accessibilityLabel: String {
        let tools = columns.isEmpty ? [tool] : columns
        let limits = tools.map { summary in
            let rows = summary.rows.map(\.accessibilityText)
            return ([summary.name] + (rows.isEmpty ? [summary.status ?? "no data"] : rows)).joined(separator: ", ")
        }
        let sessions = count.map { "\($0) active session\($0 == 1 ? "" : "s")" } ?? "No active sessions"
        return (limits + [sessions, footer.text]).joined(separator: ". ")
    }
}
