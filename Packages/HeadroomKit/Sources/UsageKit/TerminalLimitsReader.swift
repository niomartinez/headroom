import Foundation
import HeadroomModel

/// Reads `~/.claude/headroom/statusline-latest.json` (spec §2.4).
public struct TerminalLimitsReader: Sendable {
    /// A status line payload is a few KB.
    static let maxFileSize = 1024 * 1024

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `nil` when the file is missing or has no `rate_limits`.
    ///
    /// observedAt = the file's mtime, or the newest API reply in the payload's `transcript_path` when that is
    /// older: Claude Code re-runs the status line from cached rate limits without an API call (at the earliest
    /// `resets_at`, at prompt-cache expiry, on UI changes), and each re-run rewrites the file with the old numbers.
    /// Without a readable transcript the mtime is kept.
    public func read() -> PlanUsage? {
        read(willReadTranscript: { _ in })
    }

    /// `read()`, calling `willReadTranscript` with the payload's `transcript_path` just before that transcript
    /// is read (never when none is). A caller that caches the reading keys it on the transcript as it was then:
    /// the reply that dates the numbers can reach the transcript after the status line wrote the file.
    public func read(willReadTranscript: (String) -> Void) -> PlanUsage? {
        guard case .file(let data, let modified?) = readRegularFile(at: fileURL, limit: Self.maxFileSize),
              let payload = try? JSONDecoder().decode(StatusLinePayload.self, from: data),
              let limits = payload.rateLimits
        else { return nil }
        let newestReply = payload.transcriptPath.flatMap { path -> Date? in
            willReadTranscript(path)
            return TranscriptReplyTime.newestReply(inTranscriptAt: path)
        }
        return Self.usage(from: limits, observedAt: min(modified, newestReply ?? modified))
    }

    /// The exact readings in a raw status line payload's `rate_limits` (`resets_at` in epoch seconds).
    /// A limit with a missing or non-numeric `used_percentage` is skipped; `nil` when none is left.
    /// A `resets_at` that looks like milliseconds (> 10^11) is divided by 1000; one before 2020 or
    /// more than 400 days after `observedAt` is dropped (reset unknown).
    public static func limits(fromStatusLinePayload data: Data, observedAt: Date) -> PlanUsage? {
        guard let limits = (try? JSONDecoder().decode(StatusLinePayload.self, from: data))?.rateLimits else {
            return nil
        }
        return usage(from: limits, observedAt: observedAt)
    }

    private static func usage(from limits: RateLimits, observedAt: Date) -> PlanUsage? {
        let usage = PlanUsage(
            fiveHour: limits.fiveHour?.reading(.fiveHour, observedAt: observedAt),
            weekly: limits.sevenDay?.reading(.weekly, observedAt: observedAt)
        )
        return usage.isEmpty ? nil : usage
    }
}

// Nested values decode leniently: a malformed part becomes nil instead of failing the whole payload.

private struct StatusLinePayload: Decodable {
    let rateLimits: RateLimits?
    let transcriptPath: String?

    private enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
        case transcriptPath = "transcript_path"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rateLimits = try? container.decodeIfPresent(RateLimits.self, forKey: .rateLimits)
        transcriptPath = try? container.decodeIfPresent(String.self, forKey: .transcriptPath)
    }
}

private struct RateLimits: Decodable {
    let fiveHour: RateLimit?
    let sevenDay: RateLimit?

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try? container.decodeIfPresent(RateLimit.self, forKey: .fiveHour)
        sevenDay = try? container.decodeIfPresent(RateLimit.self, forKey: .sevenDay)
    }
}

private struct RateLimit: Decodable {
    let usedPercentage: Double?
    let resetsAt: Double?

    private enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercentage = try? container.decodeIfPresent(Double.self, forKey: .usedPercentage)
        resetsAt = try? container.decodeIfPresent(Double.self, forKey: .resetsAt)
    }

    func reading(_ kind: LimitKind, observedAt: Date) -> LimitReading? {
        usedPercentage.map {
            LimitReading(
                kind: kind, usedPercent: $0,
                resetsAt: resetsAt.flatMap { ResetTimeSanity.date(fromEpoch: $0, observedAt: observedAt) },
                resetIsEstimated: false, observedAt: observedAt, source: .terminal
            )
        }
    }
}

/// `resets_at` is epoch seconds (spec §2.4). A value that can't be a reset time of this reading
/// becomes "unknown" rather than a wrong date in the UI.
enum ResetTimeSanity {
    /// Above this a value is taken as epoch milliseconds (as seconds it would be past year 5000).
    static let millisecondsThreshold: Double = 1e11
    /// 2020-01-01T00:00:00Z: nothing earlier is a real reset time.
    static let earliest = Date(timeIntervalSince1970: 1_577_836_800)
    /// A weekly window is 7 days; far beyond that is garbage.
    static let maxAheadOfReading: TimeInterval = 400 * 24 * 3600

    static func date(fromEpoch value: Double, observedAt: Date) -> Date? {
        guard value.isFinite else { return nil }
        let seconds = value > millisecondsThreshold ? value / 1000 : value
        let date = Date(timeIntervalSince1970: seconds)
        guard date >= earliest, date <= observedAt.addingTimeInterval(maxAheadOfReading) else { return nil }
        return date
    }
}
