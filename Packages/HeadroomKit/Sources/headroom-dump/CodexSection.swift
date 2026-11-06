import CodexKit
import Foundation
import HeadroomModel

/// headroom-dump's `codex` section (1.1 §7): limits, plan, session counts per activity and issues. Session names
/// only with `--names`; paths never.
struct CodexSection: Encodable, Equatable {
    struct Limit: Encodable, Equatable {
        var window: String
        var usedPercent: Double?
        var resetsAt: Date?
        var resetSinceReading: Bool
        var observedAt: Date
    }

    struct Bucket: Encodable, Equatable {
        var name: String
        var limits: [Limit]
    }

    struct Sessions: Encodable, Equatable {
        var total: Int
        var working: Int
        var waitingForInput: Int
        var idle: Int
        /// Only with `--names`.
        var names: [String]?
    }

    /// `readable` or `missing`.
    var folder: String
    var status: String
    var plan: String?
    var hasFiveHourWindow: Bool
    var stale: Bool
    var limits: [Limit]
    var otherBuckets: [Bucket]
    var sessions: Sessions
    /// Whether a process named `codex` runs; nil when the process list can't be read.
    var codexRunning: Bool?
    var issues: [String]

    init(reading: CodexReading, folderExists: Bool, names: Bool, now: Date, codexRunning: Bool?) {
        func limit(_ limit: ToolLimit) -> Limit {
            Limit(
                window: limit.window.title, usedPercent: limit.usedPercent, resetsAt: limit.resetsAt,
                resetSinceReading: limit.resetSinceReading, observedAt: limit.observedAt
            )
        }
        let usage = reading.usage
        folder = folderExists ? "readable" : "missing"
        status = usage.status.rawValue
        plan = usage.planName
        hasFiveHourWindow = usage.hasFiveHourWindow
        stale = usage.isStale(now: now)
        limits = usage.limits.map(limit)
        otherBuckets = usage.otherBuckets.map { Bucket(name: $0.name, limits: $0.limits.map(limit)) }
        let sessions = reading.sessions
        self.sessions = Sessions(
            total: sessions.count,
            working: sessions.filter { $0.activity == .working }.count,
            waitingForInput: sessions.filter { $0.activity == .waitingForInput }.count,
            idle: sessions.filter { $0.activity == .idle }.count,
            names: names ? sessions.sortedForDisplay().map { "\($0.name) · \($0.activity.rawValue)" } : nil
        )
        self.codexRunning = codexRunning
        issues = reading.issues.map(\.rawValue).sorted()
    }
}
