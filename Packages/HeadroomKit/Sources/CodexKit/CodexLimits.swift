import Foundation
import HeadroomModel

/// One window of a Codex rate-limit reading.
struct RateWindow: Sendable, Equatable {
    var minutes: Int
    var usedPercent: Double
    var resetsAt: Date?
}

/// A decoded `rate_limits` object from one `token_count` line (1.1 §3.4).
struct RateReading: Sendable, Equatable {
    /// The line's own `timestamp`: readings are ordered by it, never by file dates.
    var observedAt: Date
    /// `limit_id`, "codex" when missing.
    var bucketID: String
    /// `limit_name`.
    var bucketName: String?
    /// Empty for a known empty bucket (`premium`: both windows null).
    var windows: [RateWindow]
    /// `plan_type`.
    var planType: String?

    static let mainBucket = "codex"
}

enum RateLimitDecoding: Sendable, Equatable {
    case reading(RateReading)
    /// Not a shape Codex is known to write: no numbers are guessed from it (1.1 §0.1 invariant 6).
    case unrecognized
}

enum CodexLimits {
    /// Codex's own fallback when `window_minutes` is missing: primary 5 hours, secondary a week (1.1 §3.2).
    static let primaryFallbackMinutes = 300
    static let secondaryFallbackMinutes = 10_080

    /// Decodes every `rate_limits` variant (1.1 §3.2): nested windows with `resets_at` (epoch seconds; 13 digits
    /// read as milliseconds) or `resets_in_seconds` (from the line's time), the flat ~v0.40 form (no reset times),
    /// and known empty buckets. A window that can't be read makes the whole object unrecognized.
    static func decode(_ raw: RawRateLimits, at lineTime: Date) -> RateLimitDecoding {
        var windows: [RateWindow] = []
        for (slot, fallback) in [(raw.primary, primaryFallbackMinutes), (raw.secondary, secondaryFallbackMinutes)] {
            switch slot {
            case .absent, .null:
                continue
            case .malformed:
                return .unrecognized
            case .window(let window):
                guard let used = window.usedPercent, used.isFinite, used >= 0,
                      let minutes = wholeMinutes(window.windowMinutes, fallback: fallback)
                else { return .unrecognized }
                windows.append(RateWindow(minutes: minutes, usedPercent: used, resetsAt: resetDate(window, lineTime: lineTime)))
            }
        }
        let flat = [
            (raw.primaryUsedPercent, raw.primaryWindowMinutes, primaryFallbackMinutes),
            (raw.secondaryUsedPercent, raw.secondaryWindowMinutes, secondaryFallbackMinutes),
        ]
        for (used, minutes, fallback) in flat where used != nil || minutes != nil {
            guard let used, used.isFinite, used >= 0, let minutes = wholeMinutes(minutes, fallback: fallback) else {
                return .unrecognized
            }
            windows.append(RateWindow(minutes: minutes, usedPercent: used, resetsAt: nil))
        }
        guard !windows.isEmpty || raw.hasSnapshotKeys else { return .unrecognized }
        return .reading(RateReading(
            observedAt: lineTime,
            bucketID: raw.limitID ?? RateReading.mainBucket,
            bucketName: raw.limitName,
            windows: windows,
            planType: raw.planType
        ))
    }

    /// A positive whole number of minutes that names a window (`WindowKind(windowMinutes:)`), or the fallback when
    /// the field is missing.
    private static func wholeMinutes(_ value: Double?, fallback: Int) -> Int? {
        guard let value else { return fallback }
        guard value.isFinite, value == value.rounded(), value > 0, value < 1e9 else { return nil }
        return Int(value)
    }

    private static func resetDate(_ window: RawWindow, lineTime: Date) -> Date? {
        if let at = window.resetsAt, at.isFinite, at > 0 {
            return Date(timeIntervalSince1970: at >= 1e12 ? at / 1_000 : at)
        }
        if let seconds = window.resetsInSeconds, seconds.isFinite, seconds >= 0 {
            return lineTime.addingTimeInterval(seconds)
        }
        return nil
    }

    /// `plan_type` for display: plus → "Plus", pro → "Pro", prolite → "Pro Lite", anything else capitalized;
    /// none → nil (1.1 §3.4).
    static func planName(_ planType: String?) -> String? {
        guard let planType = planType?.trimmingCharacters(in: .whitespacesAndNewlines), !planType.isEmpty else {
            return nil
        }
        switch planType.lowercased() {
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "prolite", "pro_lite", "pro-lite": return "Pro Lite"
        default: return planType.prefix(1).uppercased() + planType.dropFirst()
        }
    }

    /// The limits of one reading, longest window first. A window whose length names no window is dropped, which
    /// `decode` already rules out.
    static func limits(of reading: RateReading) -> [ToolLimit] {
        reading.windows
            .compactMap { window in
                WindowKind(windowMinutes: window.minutes).map {
                    ToolLimit(window: $0, usedPercent: window.usedPercent, resetsAt: window.resetsAt, observedAt: reading.observedAt)
                }
            }
            .sorted { $0.window.lengthMinutes > $1.window.lengthMinutes }
    }

    /// The Codex `ToolUsage` from the newest reading of each bucket (1.1 §3.4), not yet rolled over:
    /// - the rings use only the `codex` bucket, each window mapped by its length, from primary or secondary alike;
    /// - `hasFiveHourWindow` when that reading has a ≈300-minute window;
    /// - other buckets with at least one window go to `otherBuckets`, named `limit_name ?? limit_id`;
    /// - `.ok` with a `codex` window, else `.noActivity`.
    static func usage(from best: [String: RateReading]) -> ToolUsage {
        let main = best[RateReading.mainBucket]
        let mainLimits = main.map { limits(of: $0) } ?? []
        var others: [NamedLimits] = []
        for (id, reading) in best where id != RateReading.mainBucket {
            let bucketLimits = limits(of: reading)
            guard !bucketLimits.isEmpty else { continue }
            let name = reading.bucketName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            others.append(NamedLimits(id: id, name: name.isEmpty ? id : name, limits: bucketLimits))
        }
        others.sort { ($0.name, $0.id) < ($1.name, $1.id) }
        return ToolUsage(
            tool: .codex,
            limits: mainLimits,
            hasFiveHourWindow: mainLimits.contains { $0.window == .fiveHour },
            otherBuckets: others,
            status: mainLimits.isEmpty ? .noActivity : .ok,
            planName: planName(main?.planType)
        )
    }
}

/// Keeps the last good Codex usage while the newest `rate_limits` is unrecognized, for up to 5 minutes, before
/// reporting `.unrecognized` (1.1 §3.4, as 1.0 §2.1 does for the desktop file: it may be a one-off).
struct UnrecognizedHold: Sendable {
    static let grace: TimeInterval = 5 * 60

    private(set) var lastGood: ToolUsage?
    private(set) var unrecognizedSince: Date?

    /// `usage`: what the readings give. `newestIsUnrecognized`: the newest non-null `rate_limits` decodes to no
    /// window and isn't a known empty bucket. Returns the usage to show and whether to report the issue.
    mutating func resolve(usage: ToolUsage, newestIsUnrecognized: Bool, now: Date) -> (usage: ToolUsage, issue: Bool) {
        guard newestIsUnrecognized else {
            unrecognizedSince = nil
            lastGood = usage.status == .ok ? usage : nil
            return (usage, false)
        }
        let since = unrecognizedSince ?? now
        unrecognizedSince = since
        if let lastGood, now.timeIntervalSince(since) < Self.grace {
            return (lastGood, false)
        }
        lastGood = nil
        return (ToolUsage(tool: .codex, status: .unrecognized), true)
    }
}
