import Foundation
import HeadroomModel

/// What the widgets show of a snapshot, coarsely (1.1 §5.4): the app rewrites the shared file and reloads the
/// widgets only when this changes (or on a heartbeat), not on every 2-second poll. Pure.
public struct WidgetSignature: Sendable, Equatable {
    /// One limit as a widget draws it: the rounded percent and its severity.
    public struct Limit: Sendable, Equatable {
        public var window: WindowKind
        /// Nil when the limit has no percent (Copilot without a known allowance).
        public var percent: Int?
        public var severity: Severity?

        public init(window: WindowKind, percent: Int?, severity: Severity?) {
            self.window = window
            self.percent = percent
            self.severity = severity
        }
    }

    /// One tracked tool: its limits (longest window first) and its status.
    public struct Tool: Sendable, Equatable {
        public var tool: ToolID
        public var status: ToolStatus
        public var limits: [Limit]

        public init(tool: ToolID, status: ToolStatus, limits: [Limit]) {
            self.tool = tool
            self.status = status
            self.limits = limits
        }
    }

    /// One of the first `topSessionCount` sessions in display order.
    public struct Session: Sendable, Equatable {
        public var id: String
        public var activity: SessionActivity
        /// The context percent rounded to 5, or nil without one (or when the window is only a guess).
        public var context: Int?

        public init(id: String, activity: SessionActivity, context: Int?) {
            self.id = id
            self.activity = activity
            self.context = context
        }
    }

    /// The most sessions any widget lists (Sessions · large shows 6) plus one, so a seventh moving up is noticed.
    public static let topSessionCount = 7

    public var tools: [Tool]
    public var activeCount: Int
    public var waitingCount: Int
    public var topSessions: [Session]
    public var issues: Set<DataIssue>
    public var isSample: Bool
    public var pillTool: ToolID?
    public var showsSessionNames: Bool

    public init(snapshot: HeadroomSnapshot, isSample: Bool, pillTool: ToolID?, showsSessionNames: Bool) {
        tools = snapshot.trackedTools.compactMap { tool in
            snapshot.usage(for: tool).map { usage in
                Tool(tool: tool, status: usage.status, limits: usage.limits.map(Self.limit))
            }
        }
        activeCount = snapshot.activeCount
        waitingCount = snapshot.waitingCount
        topSessions = snapshot.sessions.prefix(Self.topSessionCount).map { session in
            Session(id: session.id, activity: session.activity, context: Self.roundedContext(session.context))
        }
        issues = snapshot.issues
        self.isSample = isSample
        self.pillTool = pillTool
        self.showsSessionNames = showsSessionNames
    }

    /// The severity of every limit, in order, for telling an urgent change (a color changed) from a routine one.
    public var severities: [ToolID: [Severity?]] {
        Dictionary(uniqueKeysWithValues: tools.map { ($0.tool, $0.limits.map(\.severity)) })
    }

    private static func limit(_ limit: ToolLimit) -> Limit {
        guard let used = limit.usedPercent, used.isFinite else {
            return Limit(window: limit.window, percent: nil, severity: nil)
        }
        // Rounded the way the UI rounds (HeadroomFormat.roundedPercent), and judged on that rounded number.
        let percent = Int(min(100, max(0, used)).rounded())
        return Limit(window: limit.window, percent: percent, severity: Thresholds.limits.severity(for: Double(percent)))
    }

    private static func roundedContext(_ context: ContextUsage?) -> Int? {
        guard let context, !context.windowIsAssumed, context.windowTokens > 0 else { return nil }
        let percent = context.percent
        guard percent.isFinite else { return nil }
        return Int((percent / 5).rounded()) * 5
    }
}
