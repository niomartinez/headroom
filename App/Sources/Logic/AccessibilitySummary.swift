import Foundation
import HeadroomModel
import HeadroomUI

/// What VoiceOver says for the pill: the moment being shown, missing folder access, the limits
/// and the sessions. It is the only thing VoiceOver reads for the menu bar item, so like the panel
/// it never reads data it couldn't see as "nothing there" (spec §4). With only Claude tracked it is 1.0's label; with
/// more tools, the limits are the status item's tooltip, one sentence per tool (1.1 §6.1).
///
/// 1.1 §14.4: while the pill rests on "(!) harbor", the label starts with who needs you; waits the user dismissed are
/// counted apart ("1 needs input, 1 dismissed"), like the pill's count leaves them out.
enum AccessibilitySummary {
    /// `sampleData`: the snapshot is made up (sample data mode), and VoiceOver says so first. `attention`: the pill's
    /// needs-you rest state. `dismissedIDs`: waits the user dismissed, whether `snapshot` still says waiting or already
    /// reads them as idle (`NeedsYouPresentation`).
    static func label(
        for snapshot: HeadroomSnapshot,
        moment: Moment?,
        now: Date,
        sampleData: Bool = false,
        attention: NeedsYouAttention? = nil,
        dismissedIDs: Set<String> = []
    ) -> String {
        var sentences = ["Headroom"]
        if sampleData {
            sentences.append("Showing sample data")
        }
        if let moment {
            sentences.append(text(for: moment, trackedTools: snapshot.trackedTools))
        } else if let attention {
            sentences.append(attention.spoken)
        }
        let issues = snapshot.issues
        if let access = accessSentence(issues) {
            sentences.append(access)
        }
        if isClaudeLabel(snapshot) {
            sentences.append(contentsOf: limitSentences(snapshot.plan, issues: issues, now: now))
            if let sessions = sessionSentence(snapshot.sessions, issues: issues, dismissedIDs: dismissedIDs) {
                sentences.append(sessions)
            }
        } else {
            if let limits = toolLimitsSentence(snapshot, now: now) {
                sentences.append(limits)
            }
            if let sessions = toolsSessionSentence(snapshot, dismissedIDs: dismissedIDs) {
                sentences.append(sessions)
            }
        }
        return sentences.joined(separator: ". ") + "."
    }

    /// 1.0's words while only Claude is tracked; else the pill's (`MomentDisplay`), which name a limit's tool and, for
    /// VoiceOver, a session's: "Codex session ledger finished" (1.1 §6.2).
    static func text(for moment: Moment, trackedTools: [ToolID] = [.claude]) -> String {
        guard trackedTools.isEmpty || trackedTools == [.claude] else {
            return MomentDisplay(moment, trackedTools: trackedTools).spokenText
        }
        switch moment {
        case let .sessionFinished(_, name):
            return "\(name) finished"
        case let .sessionNeedsInput(_, name):
            return "\(name) needs your input"
        case let .limitCrossed(kind, percent):
            return percent >= 100 ? "\(title(kind)) limit reached" : "\(title(kind)) limit at \(percent)%"
        case let .toolLimitCrossed(tool, window, percent):
            return percent >= 100
                ? "\(tool.shortName) \(window.title.lowercased()) limit reached"
                : "\(tool.shortName) \(window.title.lowercased()) limit at \(percent)%"
        }
    }

    /// Only Claude tracked (or nothing at all): 1.0's label.
    private static func isClaudeLabel(_ snapshot: HeadroomSnapshot) -> Bool {
        snapshot.trackedTools.isEmpty || snapshot.isClaudeOnly
    }

    /// The status item's tooltip without its final period: "Claude weekly 89%, 5-hour 14%. Codex weekly 94%. Copilot
    /// 34% of monthly credits".
    private static func toolLimitsSentence(_ snapshot: HeadroomSnapshot, now: Date) -> String? {
        guard let limits = PillModel(snapshot: snapshot, moment: nil, now: now).toolTip, !limits.isEmpty else { return nil }
        return limits.hasSuffix(".") ? String(limits.dropLast()) : limits
    }

    /// With more than Claude tracked, the panel's words (1.1 §6.3): the sessions, "No sessions running", "No Codex
    /// sessions running", or "Can't read Codex sessions"; nil while the access sentence explains an empty list.
    private static func toolsSessionSentence(_ snapshot: HeadroomSnapshot, dismissedIDs: Set<String>) -> String? {
        let issues = snapshot.issues
        let tracked = snapshot.trackedTools
        let unreadable = [
            snapshot.claudeTracked && issues.contains(.sessionRegistryUnreadable) ? "Claude Code" : nil,
            tracked.contains(.codex) && issues.contains(.codexSessionsUnreadable) ? "Codex" : nil,
        ].compactMap { $0 }
        let cantRead = unreadable.isEmpty ? nil : "Can't read \(unreadable.joined(separator: " or ")) sessions"
        guard snapshot.sessions.isEmpty else {
            return [sessionCounts(snapshot.sessions, dismissedIDs: dismissedIDs), cantRead].compactMap { $0 }
                .joined(separator: ". ")
        }
        let claudeBlocked = !snapshot.claudeTracked || issues.contains(.claudeCodeFolderUnavailable)
        let codexBlocked = !tracked.contains(.codex) || issues.contains(.codexFolderUnavailable)
        if claudeBlocked, codexBlocked, !tracked.contains(.copilot) { return nil }
        if let cantRead { return cantRead }
        switch tracked {
        case [.codex]: return "No Codex sessions running"
        case [.copilot]: return "No Copilot CLI sessions running"
        default: return "No sessions running"
        }
    }

    /// The panel's "Give access" row, in the same words: 1.0's with only Claude's folders missing, merged with
    /// Codex's (1.1 §6.3).
    private static func accessSentence(_ issues: Set<DataIssue>) -> String? {
        let claude: String? = switch (issues.contains(.claudeCodeFolderUnavailable), issues.contains(.desktopFolderUnavailable)) {
        case (true, true): "Needs access to your Claude folders"
        case (true, false): "Needs access to ~/.claude to see sessions"
        case (false, true): "Needs access to the Claude app's folder to read limits"
        case (false, false): nil
        }
        guard issues.contains(.codexFolderUnavailable) else { return claude }
        return claude == nil ? "Needs access to ~/.codex to see Codex" : "Needs access to your Claude and Codex folders"
    }

    private static func limitSentences(_ plan: PlanUsage, issues: Set<DataIssue>, now: Date) -> [String] {
        guard !plan.isEmpty else {
            if issues.contains(.desktopUsageUnrecognized) { return ["Usage data not recognized"] }
            // Without the Claude app's folder the access sentence already says why there are no limits.
            if issues.contains(.desktopFolderUnavailable) { return [] }
            return ["No plan usage yet"]
        }
        return [plan.weekly, plan.fiveHour].compactMap { reading in
            guard let reading else { return nil }
            var sentence: String
            if reading.kind == .fiveHour, reading.usedPercent <= 0, reading.resetsAt == nil {
                sentence = "\(title(reading.kind)) limit not started"
            } else {
                let percent = Int(min(max(reading.usedPercent, 0), 100).rounded())
                sentence = "\(title(reading.kind)) limit \(percent)% used"
            }
            if reading.isStale(now: now) {
                sentence += ", as of \(age(since: reading.observedAt, now: now)) ago"
            }
            return sentence
        }
    }

    /// Nil when the access sentence already explains why no sessions are listed.
    private static func sessionSentence(
        _ sessions: [SessionInfo], issues: Set<DataIssue>, dismissedIDs: Set<String>
    ) -> String? {
        guard !sessions.isEmpty else {
            if issues.contains(.claudeCodeFolderUnavailable) { return nil }
            return issues.contains(.sessionRegistryUnreadable)
                ? "Can't read Claude Code sessions"
                : "No Claude Code sessions running"
        }
        return sessionCounts(sessions, dismissedIDs: dismissedIDs)
    }

    /// "Sessions: 2 working, 1 needs input, 1 dismissed, 3 idle".
    private static func sessionCounts(_ sessions: [SessionInfo], dismissedIDs: Set<String>) -> String {
        let isDismissed = { (session: SessionInfo) in
            session.activity != .working && dismissedIDs.contains(session.id)
        }
        let working = sessions.filter { $0.activity == .working }.count
        let waiting = sessions.filter { $0.activity == .waitingForInput && !isDismissed($0) }.count
        let dismissed = sessions.filter(isDismissed).count
        let idle = sessions.filter { $0.activity == .idle && !isDismissed($0) }.count
        let parts = [
            working > 0 ? "\(working) working" : nil,
            waiting > 0 ? "\(waiting) \(waiting == 1 ? "needs" : "need") input" : nil,
            dismissed > 0 ? "\(dismissed) dismissed" : nil,
            idle > 0 ? "\(idle) idle" : nil,
        ].compactMap { $0 }
        return "Sessions: " + parts.joined(separator: ", ")
    }

    private static func title(_ kind: LimitKind) -> String {
        switch kind {
        case .fiveHour: "5-hour"
        case .weekly: "Weekly"
        }
    }

    /// Minutes, hours, then days, like the panel's "42m ago", "3h ago", "3d ago".
    private static func age(since date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 60 {
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        let hours = minutes / 60
        if hours < 24 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        let days = hours / 24
        return days == 1 ? "1 day" : "\(days) days"
    }
}
