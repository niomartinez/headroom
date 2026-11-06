import Foundation
import HeadroomModel

/// Everything the dropdown panel shows, computed from a snapshot (spec §1.2). Pure: no SwiftUI.
public struct PanelModel: Sendable, Equatable {
    /// One header row: `Weekly … 89%` over `resets Sun 7 PM`.
    public struct LimitRow: Sendable, Equatable {
        public var title: String
        /// Nil when there is no trustworthy number; the view shows a dash.
        public var badge: PercentBadge?
        public var detail: String
        /// Gray lines under `detail`: Copilot's amount, "512 of 1,500 credits" (1.1 §6.3).
        public var lines: [String] = []
        /// What VoiceOver reads after the label: "89% used, resets about Sunday 7 PM". Words for
        /// what the text shows with marks: "about" for "~", the reason for "–".
        public var accessibilityValue: String = ""
        /// The gauge ring the row is, for its ring key (1.1 §14.2): outer for the longest window, inner for the
        /// 5-hour one. Nil when the gauge draws only one ring (no key needed).
        public var ring: GaugeRing? = nil

        /// "Weekly limit".
        public var accessibilityLabel: String { "\(title) limit" }
    }

    /// The big gauge and its rows (spec §1.2 item 1): the pill's tool (1.1 §6.3).
    public struct Header: Sendable, Equatable {
        /// The tool shown; nil when no tool is tracked (1.0's empty header).
        public var tool: ToolID?
        /// The tool's short name above the rows, with two or more tools tracked.
        public var toolName: String?
        public var gauge: GaugeModel
        /// Longest window first. Empty when `status` explains why there are none.
        public var rows: [LimitRow]
        /// Gray lines under the rows: Claude's extra usage, other Codex buckets at 75 % or more.
        public var notes: [String]
        /// Instead of rows: "No Codex limits found", "Connect GitHub in Settings" and its button.
        public var status: ToolStatusLine?
    }

    /// A compact row for a tracked tool other than the header's (1.1 §6.3): a 24 pt gauge, the name, then one line
    /// per limit (label, percent, detail).
    public struct ToolRow: Sendable, Equatable, Identifiable {
        public struct Line: Sendable, Equatable {
            /// "Weekly".
            public var label: String
            /// "94%"; empty without a percent (Copilot without a plan), "–" for a percent that isn't a number.
            public var percent: String
            public var severity: Severity
            /// "resets Wed 9 AM", "as of 3h ago", "reset since last reading".
            public var detail: String
            /// The ring key (1.1 §14.2), for tools with two windows only.
            public var ring: GaugeRing? = nil
        }

        public var tool: ToolID
        /// "Codex".
        public var name: String
        public var gauge: GaugeModel
        public var lines: [Line]
        /// Gray lines under the limit lines: Copilot's amount, other Codex buckets at 75 % or more.
        public var notes: [String]
        /// Instead of lines: "No Codex limits found", "Sign-in expired" and its button.
        public var status: ToolStatusLine?
        /// Hover: the plan, exact resets and how old the reading is.
        public var helpText: String?
        /// "Codex limits".
        public var accessibilityLabel: String
        /// "weekly 94% used, resets Wednesday 9 AM; 5-hour 20% used, resets in 1 hour 10 minutes".
        public var accessibilityValue: String

        public var id: ToolID { tool }
    }

    public enum SectionKind: Sendable, Hashable {
        case working
        case needsYou
        /// Finished, not yet reviewed (1.1.1, `FinishedTracker`).
        case justFinished
        case idle
    }

    public struct Section: Sendable, Equatable, Identifiable {
        public var kind: SectionKind
        public var title: String
        /// The rows to draw (idle is cut to `collapsedIdleCount` unless expanded).
        public var rows: [SessionRow]
        /// Rows not drawn because the section is collapsed.
        public var hiddenCount: Int
        /// "Show 4 more" / "Show less"; nil when there is nothing to toggle.
        public var toggleTitle: String?
        /// "Clear" after Just finished's title: every row moves to Idle. Nil elsewhere and in sample data.
        public var clearTitle: String? = nil

        public var id: SectionKind { kind }
    }

    /// A Needs you row's mark (1.1 §14.4).
    public enum RowAttention: Sendable, Equatable {
        case none
        /// Waiting, and not seen before this panel opened: a faint amber wash.
        case unseen
        /// Still waiting, but the user dismissed it: last in Needs you, a hollow amber dot at 70 %, a gray name.
        case dismissed
        /// In Just finished: done, not yet reviewed.
        case finished
    }

    public struct SessionRow: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        /// Project folder; nil for scratch workspaces or when equal to the name.
        public var projectName: String?
        public var isTerminal: Bool
        /// "Codex": the session's tool, only when the list mixes tools (1.1 §6.3).
        public var toolTag: String? = nil
        public var dot: DotState
        public var context: ContextBadge?
        /// Hover text: "724k of 1M tokens · claude-opus-5-5", or "168k tokens · claude-opus-4-5" when
        /// the window size is a guess; "Dismissed · still waiting" first on a dismissed row.
        public var helpText: String?
        /// Where a click goes (1.1 §14.3): "Open in Claude", "Show in Terminal". Nil: the row isn't a button.
        public var openTitle: String? = nil
        public var attention: RowAttention = .none
        /// A waiting or just-finished row the user can dismiss (not in sample data).
        public var canDismiss = false

        /// What VoiceOver reads for the row: "Refactor invoice export, ledger, working", with
        /// "terminal" and the tool tag before the state when shown, and "new" or "dismissed" after a waiting one.
        public var accessibilityLabel: String {
            let mark: String? = switch attention {
            case .none: nil
            case .unseen: "new"
            case .dismissed: "dismissed"
            case .finished: "finished"
            }
            return [name, projectName, isTerminal ? "terminal" : nil, toolTag, dot.spokenState, mark]
                .compactMap { $0 }
                .joined(separator: ", ")
        }

        /// The tooltip, which macOS also reads as the VoiceOver hint: "Open in Claude · 720k of 1M tokens · model".
        public var tooltip: String {
            [openTitle, helpText].compactMap { $0 }.joined(separator: " · ")
        }

        /// "context 72% full", "context 168k tokens" when the window size is a guess; nil without a
        /// context reading.
        public var accessibilityValue: String? {
            context.map { $0.windowIsAssumed ? "context \($0.text) tokens" : "context \($0.text) full" }
        }
    }

    public static let collapsedIdleCount = 3

    /// What the header draws: Claude's `gauge`, `weekly`, `fiveHour` and `extraUsage`, or another tool's (1.1 §6.3).
    public var header: Header
    /// Compact rows for the other tracked tools, in display order; empty with one tool tracked.
    public var toolRows: [ToolRow]
    /// Claude's rings (the header's when it shows Claude).
    public var gauge: GaugeModel
    public var weekly: LimitRow
    public var fiveHour: LimitRow
    /// "Extra usage 12%" when reported and above 0.
    public var extraUsage: String?
    /// Shown with a `Give access` button when a folder grant is missing.
    public var accessMessage: String?
    /// "Codex found on this Mac. Show its limits and sessions here too?" with Give access / Not now, when the
    /// app offers Codex (1.1 §6.3).
    public var codexOffer: String?
    /// Only non-empty sections, in the order Working, Needs you, Just finished, Idle.
    public var sections: [Section]
    /// Session tools in display order, including collapsed idle rows, for the compact footer legend.
    public var sessionTools: [ToolID]
    /// "No Claude Code sessions running" when there is nothing to list, or "Can't read Claude Code
    /// sessions" when the session registry could not be read. "No Codex sessions running" with only Codex
    /// tracked, "No sessions running" with two or more tools (1.1 §6.3).
    public var emptyMessage: String?
    /// Under a non-empty list, with more than Claude tracked: "Can't read Codex sessions" (1.1 §3.6).
    public var sessionNotice: String?
    /// "Updated 2m ago · from the Claude app", "· from Codex", "· from GitHub"; "Updated 2m ago" with two or more
    /// tools; or "Sample data" while sample data shows.
    public var footer: String
    public var terminalConnected: Bool
    public var terminalMenuTitle: String
    /// "Preview with sample data" when Headroom found no Claude data at all (`PanelSampleData.offered`).
    public var sampleDataOffer: String?
    /// "Turn off", after the footer, while sample data shows.
    public var sampleDataTurnOff: String?

    /// `tool` is the "Rings show" choice (nil = Automatic, `RingsTool.resolve`): the header shows it. The app
    /// decides when to offer Codex (`showsCodexOffer`: undecided, installed, sample data off).
    ///
    /// "Needs you" marks (1.1 §14.4): `unseenIDs` are waiting sessions not seen before the panel opened (a wash);
    /// `dismissedIDs` are waiting sessions the user dismissed. They are listed last in Needs you whether the snapshot
    /// still says waiting or already reads them as idle (`NeedsYouTracker`'s presentation). `openTitle` says where a
    /// click on a row goes (1.1 §14.3). `finishedIDs` are idle sessions not reviewed since they finished
    /// (`FinishedTracker`): listed in Just finished instead of Idle.
    public init(
        snapshot: HeadroomSnapshot,
        now: Date,
        idleExpanded: Bool = false,
        sampleData: PanelSampleData = .hidden,
        tool: ToolID? = nil,
        showsCodexOffer: Bool = false,
        unseenIDs: Set<String> = [],
        dismissedIDs: Set<String> = [],
        finishedIDs: Set<String> = [],
        openTitles: [String: String] = [:],
        format: HeadroomFormat = HeadroomFormat()
    ) {
        let plan = snapshot.plan
        let noData = snapshot.issues.contains(.desktopUsageUnrecognized) ? "usage data not recognized" : "no data yet"
        let claudeFolderMissing = snapshot.issues.contains(.claudeCodeFolderUnavailable)
        let tracked = snapshot.trackedTools
        let isMultiTool = tracked.count > 1
        let shown = RingsTool.resolve(tool, in: snapshot)

        gauge = GaugeModel(plan: plan, now: now)
        weekly = Self.limitRow(plan.weekly, kind: .weekly, noData: noData, now: now, format: format)
        weekly.ring = .outer
        fiveHour = Self.limitRow(plan.fiveHour, kind: .fiveHour, noData: noData, now: now, format: format)
        fiveHour.ring = .inner
        extraUsage = plan.extraUsagePercent.flatMap { extra in
            guard extra.isFinite, extra > 0 else { return nil }
            return "Extra usage \(format.percent(extra))"
        }
        if let shown, shown != .claude, let usage = snapshot.usage(for: shown) {
            header = Self.toolHeader(usage, named: isMultiTool, issues: snapshot.issues, now: now, format: format)
        } else {
            header = Header(
                tool: shown, toolName: isMultiTool ? ToolID.claude.shortName : nil, gauge: gauge, rows: [weekly, fiveHour],
                notes: extraUsage.map { [$0] } ?? [], status: nil
            )
        }
        toolRows = isMultiTool
            ? tracked.filter { $0 != shown }.compactMap { tool in
                snapshot.usage(for: tool).flatMap { Self.toolRow($0, issues: snapshot.issues, now: now, format: format) }
            }
            : []
        accessMessage = Self.accessMessage(snapshot.issues)
        codexOffer = showsCodexOffer ? "Codex found on this Mac. Show its limits and sessions here too?" : nil
        sections = Self.sections(
            snapshot.sessions, idleExpanded: idleExpanded,
            marks: RowMarks(
                unseen: unseenIDs, dismissed: dismissedIDs, finished: finishedIDs, canDismiss: sampleData != .showing
            ),
            marksTool: isMultiTool, openTitles: openTitles, format: format
        )
        let presentTools = Set(snapshot.sessions.map(\.tool))
        sessionTools = ToolID.allCases.filter { presentTools.contains($0) }
        if tracked.isEmpty || tracked == [.claude] {
            emptyMessage = Self.emptyMessage(snapshot, claudeFolderMissing: claudeFolderMissing)
            sessionNotice = nil
        } else {
            (emptyMessage, sessionNotice) = Self.toolsSessionMessages(snapshot)
        }
        footer = sampleData == .showing
            ? "Sample data"
            : Self.footer(snapshot, tool: shown, isMultiTool: isMultiTool, now: now, format: format)
        terminalConnected = snapshot.terminalBridgeConnected
        terminalMenuTitle = snapshot.terminalBridgeConnected ? "Disconnect terminal" : "Connect terminal"
        sampleDataOffer = sampleData == .offered ? "Preview with sample data" : nil
        sampleDataTurnOff = sampleData == .showing ? "Turn off" : nil
    }

    // MARK: Header

    private static func limitRow(_ reading: LimitReading?, kind: LimitKind, noData: String, now: Date, format: HeadroomFormat) -> LimitRow {
        guard let reading, let badge = PercentBadge(percent: reading.usedPercent, thresholds: .limits) else {
            return LimitRow(title: kind.title, badge: nil, detail: noData, accessibilityValue: noData)
        }
        let windowEndAhead = reading.resetsAt.map { $0 > now } ?? false
        let estimated = reading.resetIsEstimated
        // The text as shown, and as spoken.
        var (detail, spoken) = switch kind {
        case .weekly:
            (format.weeklyReset(at: reading.resetsAt, estimated: estimated),
             format.spokenWeeklyReset(at: reading.resetsAt, estimated: estimated))
        case .fiveHour where !windowEndAhead && HeadroomFormat.roundedPercent(reading.usedPercent) != 0:
            // Spec §3.2: usage without a window end still ahead (unknown, or a reset that passed
            // since the snapshot) reads "reset unknown"; "not started" would contradict the percent.
            (HeadroomFormat.unknownReset, HeadroomFormat.unknownReset)
        case .fiveHour:
            (format.fiveHourReset(at: reading.resetsAt, estimated: estimated, now: now),
             format.spokenFiveHourReset(at: reading.resetsAt, estimated: estimated, now: now))
        }
        if reading.isStale(now: now) {
            detail += " · as of \(format.age(of: reading.observedAt, now: now))"
            spoken += ", as of \(format.spokenAge(of: reading.observedAt, now: now))"
        }
        return LimitRow(title: kind.title, badge: badge, detail: detail, accessibilityValue: "\(badge.text) used, \(spoken)")
    }

    /// 1.0's messages when only Claude folders are missing; merged with Codex's (1.1 §6.3).
    private static func accessMessage(_ issues: Set<DataIssue>) -> String? {
        let claude: String? = switch (issues.contains(.claudeCodeFolderUnavailable), issues.contains(.desktopFolderUnavailable)) {
        case (true, true): "Headroom needs access to your Claude folders."
        case (true, false): "Headroom needs access to ~/.claude to see sessions."
        case (false, true): "Headroom needs access to the Claude app's folder to read limits."
        case (false, false): nil
        }
        guard issues.contains(.codexFolderUnavailable) else { return claude }
        return claude == nil
            ? "Headroom needs access to ~/.codex to see Codex."
            : "Headroom needs access to your Claude and Codex folders."
    }

    // MARK: Other tools (1.1 §6.3)

    /// A Codex or Copilot header: its rows, longest window first, or its status.
    private static func toolHeader(_ usage: ToolUsage, named: Bool, issues: Set<DataIssue>, now: Date, format: HeadroomFormat) -> Header {
        let status = ToolText.statusLine(usage, issues: issues)
        let showsAge = ToolText.showsAge(usage, now: now)
        return Header(
            tool: usage.tool,
            toolName: named ? usage.tool.shortName : nil,
            gauge: GaugeModel(usage: usage, now: now),
            rows: status == nil
                ? usage.limits.map { limit in
                    var row = toolLimitRow(limit, showsAge: showsAge, now: now, format: format)
                    row.ring = ring(of: limit, in: usage)
                    return row
                }
                : [],
            notes: status == nil ? ToolText.otherBucketNotes(usage) : [],
            status: status
        )
    }

    /// `Monthly … 34%` over `resets Oct 1` and `512 of 1,500 credits`; without a plan `Monthly … –` over
    /// `512 credits used · resets Oct 1` (1.1 §4.6). Old readings add "as of 2h ago", as Claude's stale ones do.
    private static func toolLimitRow(_ limit: ToolLimit, showsAge: Bool, now: Date, format: HeadroomFormat) -> LimitRow {
        let badge = limit.usedPercent.flatMap { PercentBadge(percent: $0, thresholds: .limits) }
        var detail = format.reset(of: limit, now: now)
        var spoken = format.spokenReset(of: limit, now: now)
        var lines: [String] = []
        if let amount = ToolText.amount(limit, format: format) {
            let extra = ToolText.extraBilled(limit, format: format)
            if badge == nil {
                // No plan: the amount leads the detail; extra usage gets its own line, which wouldn't fit after it.
                detail = "\(amount) · \(detail)"
                spoken = "\(amount), \(spoken)"
                lines = extra.map { [$0] } ?? []
            } else {
                lines = [[amount, extra].compactMap { $0 }.joined(separator: " · ")]
            }
        }
        if showsAge {
            detail += " · as of \(format.age(of: limit.observedAt, now: now))"
            spoken += ", as of \(format.spokenAge(of: limit.observedAt, now: now))"
        }
        let value = ([badge.map { "\($0.text) used, \(spoken)" } ?? spoken] + lines.map { $0.replacingOccurrences(of: " · ", with: ", ") })
            .joined(separator: ", ")
        return LimitRow(title: limit.window.title, badge: badge, detail: detail, lines: lines, accessibilityValue: value)
    }

    /// The ring a tool's limit is in its gauge (1.1 §14.2): nil when the gauge has one ring (no 5-hour window).
    private static func ring(of limit: ToolLimit, in usage: ToolUsage) -> GaugeRing? {
        guard usage.hasFiveHourWindow else { return nil }
        return limit.window == .fiveHour ? .inner : .outer
    }

    /// A compact row (1.1 §6.3); nil for Copilot tracked for its CLI sessions only.
    private static func toolRow(_ usage: ToolUsage, issues: Set<DataIssue>, now: Date, format: HeadroomFormat) -> ToolRow? {
        guard usage.status != .sessionsOnly else { return nil }
        let status = ToolText.statusLine(usage, issues: issues)
        var lines: [ToolRow.Line] = []
        var notes: [String] = []
        var spoken: [String] = []
        if status == nil {
            // An old reading says how old it is in place of the first reset that is still news.
            var asOf = ToolText.showsAge(usage, now: now) ? usage.newestObservation : nil
            for limit in usage.limits {
                let badge = limit.usedPercent.flatMap { PercentBadge(percent: $0, thresholds: .limits) }
                var detail = format.reset(of: limit, now: now)
                if let observed = asOf, !limit.resetSinceReading {
                    detail = "as of \(format.age(of: observed, now: now))"
                    asOf = nil
                }
                lines.append(ToolRow.Line(
                    label: limit.window.title,
                    percent: badge?.text ?? (limit.usedPercent == nil ? "" : "–"),
                    severity: badge?.severity ?? .normal,
                    detail: detail,
                    ring: ring(of: limit, in: usage)
                ))
                let reset = format.spokenReset(of: limit, now: now)
                spoken.append("\(limit.window.title.lowercased()) \(badge.map { "\($0.text) used, " } ?? "")\(reset)")
                if let amount = ToolText.amount(limit, format: format) {
                    notes.append([amount, ToolText.extraBilled(limit, format: format)].compactMap { $0 }.joined(separator: " · "))
                }
            }
            notes += ToolText.otherBucketNotes(usage)
            if ToolText.showsAge(usage, now: now), let observed = usage.newestObservation {
                spoken.append("as of \(format.spokenAge(of: observed, now: now))")
            }
        }
        return ToolRow(
            tool: usage.tool,
            name: usage.tool.shortName,
            gauge: GaugeModel(usage: usage, now: now),
            lines: lines,
            notes: notes,
            status: status,
            helpText: status == nil || usage.status == .noIndividualUsage ? ToolText.helpText(usage, now: now, format: format) : nil,
            accessibilityLabel: "\(usage.tool.shortName) limits",
            accessibilityValue: status?.message ?? (spoken + notes.map { $0.replacingOccurrences(of: " · ", with: ", ") })
                .joined(separator: "; ")
        )
    }

    // MARK: Sessions

    /// Nil while there are rows, or when the folder prompt already explains the empty list. An
    /// unreadable registry must not read as "nothing running" (spec §4, failure handling).
    private static func emptyMessage(_ snapshot: HeadroomSnapshot, claudeFolderMissing: Bool) -> String? {
        guard snapshot.sessions.isEmpty, !claudeFolderMissing else { return nil }
        return snapshot.issues.contains(.sessionRegistryUnreadable)
            ? "Can't read Claude Code sessions"
            : "No Claude Code sessions running"
    }

    /// With more than Claude tracked (1.1 §3.6, §6.3): the empty list's message, or a notice under the list when a
    /// tool's sessions can't be read. Nothing while every tracked session source waits for folder access (the
    /// access row explains).
    private static func toolsSessionMessages(_ snapshot: HeadroomSnapshot) -> (empty: String?, notice: String?) {
        let issues = snapshot.issues
        let tracked = snapshot.trackedTools
        let unreadable = [
            snapshot.claudeTracked && issues.contains(.sessionRegistryUnreadable) ? "Claude Code" : nil,
            tracked.contains(.codex) && issues.contains(.codexSessionsUnreadable) ? "Codex" : nil,
        ].compactMap { $0 }
        let cantRead = unreadable.isEmpty ? nil : "Can't read \(unreadable.joined(separator: " or ")) sessions"
        guard snapshot.sessions.isEmpty else { return (nil, cantRead) }

        let claudeBlocked = !snapshot.claudeTracked || issues.contains(.claudeCodeFolderUnavailable)
        let codexBlocked = !tracked.contains(.codex) || issues.contains(.codexFolderUnavailable)
        if claudeBlocked, codexBlocked, !tracked.contains(.copilot) { return (nil, nil) }
        if let cantRead { return (cantRead, nil) }
        let empty = switch tracked {
        case [.codex]: "No Codex sessions running"
        case [.copilot]: "No Copilot CLI sessions running"
        default: "No sessions running"
        }
        return (empty, nil)
    }

    /// The "needs you" marks the rows are built with.
    private struct RowMarks {
        var unseen: Set<String>
        var dismissed: Set<String>
        /// Idle sessions not reviewed since they finished.
        var finished: Set<String>
        /// False in sample data: nothing there can be dismissed.
        var canDismiss: Bool

        func isFinished(_ session: SessionInfo) -> Bool {
            finished.contains(session.id) && session.activity == .idle && !isDismissed(session)
        }

        /// A dismissed session that still waits: the snapshot may already read it as idle.
        func isDismissed(_ session: SessionInfo) -> Bool {
            dismissed.contains(session.id) && session.activity != .working
        }
    }

    /// Groups keep the snapshot's order (already sorted, spec §3.3). Dismissed waits come last in Needs you
    /// (1.1 §14.4). Finished idle sessions go to Just finished, which is never collapsed.
    private static func sections(
        _ sessions: [SessionInfo], idleExpanded: Bool, marks: RowMarks, marksTool: Bool,
        openTitles: [String: String], format: HeadroomFormat
    ) -> [Section] {
        let groups: [(SectionKind, String, SessionActivity)] = [
            (.working, "Working", .working),
            (.needsYou, "Needs you", .waitingForInput),
            (.justFinished, "Just finished", .idle),
            (.idle, "Idle", .idle),
        ]
        // A tool's identity must not disappear when another tool's last session closes.
        let showsTool = marksTool || Set(sessions.map(\.tool)).count > 1
        let dismissed = sessions.filter(marks.isDismissed)
        let listed = sessions.filter { !marks.isDismissed($0) }
        return groups.compactMap { kind, title, activity in
            var members = listed.filter { $0.activity == activity }
            switch kind {
            case .needsYou: members += dismissed
            case .justFinished: members = members.filter(marks.isFinished)
            case .idle: members = members.filter { !marks.isFinished($0) }
            case .working: break
            }
            let rows = members.map { session in
                row(session, toolTag: showsTool, marks: marks, openTitle: openTitles[session.id], format: format)
            }
            guard !rows.isEmpty else { return nil }
            if kind == .justFinished {
                return Section(
                    kind: kind, title: title, rows: rows, hiddenCount: 0, toggleTitle: nil,
                    clearTitle: marks.canDismiss ? "Clear" : nil
                )
            }
            guard kind == .idle, rows.count > collapsedIdleCount else {
                return Section(kind: kind, title: title, rows: rows, hiddenCount: 0, toggleTitle: nil)
            }
            if idleExpanded {
                return Section(kind: kind, title: title, rows: rows, hiddenCount: 0, toggleTitle: "Show less")
            }
            let hidden = rows.count - collapsedIdleCount
            return Section(
                kind: kind, title: title, rows: Array(rows.prefix(collapsedIdleCount)),
                hiddenCount: hidden, toggleTitle: "Show \(hidden) more"
            )
        }
    }

    /// "Dismissed · still waiting" before the context help of a dismissed row.
    static let dismissedHelp = "Dismissed · still waiting"

    private static func row(
        _ session: SessionInfo, toolTag: Bool, marks: RowMarks, openTitle: String?, format: HeadroomFormat
    ) -> SessionRow {
        let context = session.context.flatMap { ContextBadge($0, format: format) }
        let contextHelp = session.context.flatMap { usage -> String? in
            guard let context else { return nil }
            let tokens = context.windowIsAssumed
                ? format.tokens(used: usage.usedTokens)
                : format.tokens(used: usage.usedTokens, window: usage.windowTokens)
            guard let model = usage.model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty else { return tokens }
            return "\(tokens) · \(model)"
        }
        let isDismissed = marks.isDismissed(session)
        let isWaiting = session.activity == .waitingForInput || isDismissed
        let isFinished = marks.isFinished(session)
        let attention: RowAttention = isDismissed
            ? .dismissed
            : isFinished ? .finished : (isWaiting && marks.unseen.contains(session.id) ? .unseen : .none)
        let helpText = isDismissed
            ? [dismissedHelp, contextHelp].compactMap { $0 }.joined(separator: " · ")
            : contextHelp
        return SessionRow(
            id: session.id,
            name: session.name.nonBlank(or: "Untitled session"),
            projectName: session.projectName,
            isTerminal: session.origin == .terminal,
            toolTag: toolTag ? session.tool.shortName : nil,
            dot: isWaiting ? .waiting : DotState(session.activity),
            context: context,
            helpText: helpText,
            openTitle: openTitle,
            attention: attention,
            canDismiss: marks.canDismiss && ((isWaiting && !isDismissed) || isFinished)
        )
    }

    // MARK: Footer

    /// 1.0's footer with only Claude; "· from Codex", "· from GitHub" with only that tool; just the age of the
    /// header tool's newest reading with two or more (1.1 §6.3).
    private static func footer(_ snapshot: HeadroomSnapshot, tool: ToolID?, isMultiTool: Bool, now: Date, format: HeadroomFormat) -> String {
        guard let tool, tool != .claude, let usage = snapshot.usage(for: tool) else {
            let plan = snapshot.plan
            let newest = [plan.weekly, plan.fiveHour].compactMap { $0 }.max { $0.observedAt < $1.observedAt }
            guard let newest else { return "No usage data yet" }
            let updated = "Updated \(format.age(of: newest.observedAt, now: now))"
            if isMultiTool { return updated }
            let source = switch newest.source {
            case .desktopApp: "from the Claude app"
            case .terminal: "from the terminal"
            }
            return "\(updated) · \(source)"
        }
        guard let newest = usage.newestObservation else { return "No usage data yet" }
        let updated = "Updated \(format.age(of: newest, now: now))"
        if isMultiTool { return updated }
        return "\(updated) · from \(tool == .copilot ? "GitHub" : tool.shortName)"
    }
}
