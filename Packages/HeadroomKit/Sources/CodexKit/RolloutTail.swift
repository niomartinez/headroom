import ContextKit
import Foundation

/// A value and the time of the line it came from.
struct Stamped<Value: Sendable & Equatable>: Sendable, Equatable {
    var value: Value
    var at: Date
}

/// What a rollout's tail says (1.1 §3.3–3.5): the newest value of each kind of line. Built newest line first;
/// merging a newer scan keeps, per field, the value from the newer line, so a rewritten file can't move a value
/// back in time.
struct RolloutTail: Sendable, Equatable {
    /// A turn starting or ending.
    struct Lifecycle: Sendable, Equatable {
        var isStart: Bool
        var turnID: String?
        var at: Date
    }

    /// The newest `token_count` with `info`.
    struct ContextSample: Sendable, Equatable {
        var usedTokens: Int
        var window: Int?
        var at: Date
    }

    /// The newest line of any kind with a timestamp: the thread's last activity (liveness, the idle cap).
    var newestEventAt: Date?
    /// The newest reading per bucket id, among readings with at least one window.
    var readings: [String: RateReading] = [:]
    /// The newest reading with only null windows (`premium`, or a `codex` object with just credits and plan): no
    /// numbers, so never a bucket's newest reading (1.1 §3.4 ignores it), but a known shape, newer than an
    /// unrecognized one it follows.
    var newestEmptyAt: Date?
    /// The newest `rate_limits` that decoded to nothing known.
    var newestUnrecognizedAt: Date?
    var lifecycle: Lifecycle?
    var context: ContextSample?
    /// `task_started.model_context_window`, when `info` has no window.
    var startedWindow: Stamped<Int>?
    /// The newest `turn_context`: its model (may be nil) and time (import continuation, 1.1 §3.5).
    var turnContext: Stamped<String?>?
    var settingsModel: Stamped<String>?

    struct InputRequest: Sendable, Equatable {
        var callID: String
        var asynchronous: Bool
        var at: Date
        var resolvedAt: Date?
    }
    var inputRequest: InputRequest?
    var inputAcknowledgedAt: Date?
    /// A turn start or user interaction bounds the search for a pending question on cold reads.
    var inputBoundaryAt: Date?

    var waitingForInputAt: Date? {
        guard let request = inputRequest, request.resolvedAt == nil,
              (inputAcknowledgedAt ?? .distantPast) < request.at else { return nil }
        // Async questions survive the turn finishing; their immediate tool output only acknowledges display.
        if !request.asynchronous, let lifecycle, !lifecycle.isStart, lifecycle.at >= request.at { return nil }
        return request.at
    }

    /// Everything the reader looks for has been found: older lines can only hold older values.
    var hasEverything: Bool {
        readings[RateReading.mainBucket] != nil && lifecycle != nil && context != nil && turnContext != nil
            && inputBoundaryAt != nil
    }

    /// The model for the context row: the newest `turn_context.model`, else `thread_settings_applied`'s.
    var model: String? {
        turnContext?.value ?? settingsModel?.value
    }

    /// Per field, the value from the newer line.
    mutating func merge(newer other: RolloutTail) {
        func newest<T>(_ a: T?, _ b: T?, _ at: (T) -> Date) -> T? {
            guard let a else { return b }
            guard let b else { return a }
            return at(b) >= at(a) ? b : a
        }
        newestEventAt = newest(newestEventAt, other.newestEventAt) { $0 }
        for (id, reading) in other.readings {
            readings[id] = newest(readings[id], reading, \.observedAt)
        }
        newestEmptyAt = newest(newestEmptyAt, other.newestEmptyAt) { $0 }
        newestUnrecognizedAt = newest(newestUnrecognizedAt, other.newestUnrecognizedAt) { $0 }
        lifecycle = newest(lifecycle, other.lifecycle, \.at)
        context = newest(context, other.context, \.at)
        startedWindow = newest(startedWindow, other.startedWindow, \.at)
        turnContext = newest(turnContext, other.turnContext, \.at)
        settingsModel = newest(settingsModel, other.settingsModel, \.at)
        inputRequest = newest(inputRequest, other.inputRequest, \.at)
        inputAcknowledgedAt = newest(inputAcknowledgedAt, other.inputAcknowledgedAt) { $0 }
        inputBoundaryAt = newest(inputBoundaryAt, other.inputBoundaryAt) { $0 }
    }
}

/// Reads rollout tails with `JSONLTailReader` (1.1 §3.3).
struct RolloutTailScanner: Sendable {
    /// Lines that can matter; everything else is skipped without decoding.
    static let needles: [[UInt8]] = [
        #""token_count""#, #""task_started""#, #""task_complete""#, #""turn_aborted""#, #""turn_started""#,
        #""turn_complete""#, #""turn_context""#, #""thread_settings_applied""#,
        #""function_call""#, #""function_call_output""#, #""role":"user""#, #""role": "user""#,
    ].map { Array($0.utf8) }

    /// Once everything is found, lines this far back from that point are still read for other buckets' readings
    /// (a Spark reading just older than the `codex` one), then the scan stops.
    static let extraBytesForOtherBuckets: Int64 = 256 * 1_024

    var reader = JSONLTailReader()

    struct Result {
        var tail: RolloutTail
        var scan: JSONLTailReader.Scan
        /// End of the older range not visited yet. Only session recovery follows this cursor.
        var historyEnd: Int64?
    }

    /// Scans `from..<size` of the open rollout newest line first, until everything is found (plus
    /// `extraBytesForOtherBuckets`) or the tail reader's 8 MB window is used up.
    func scan(
        descriptor: Int32, from start: Int64 = 0, size: Int64,
        previousRequest: RolloutTail.InputRequest? = nil
    ) -> Result {
        var tail = RolloutTail()
        tail.inputRequest = previousRequest
        // Newest-first scans see outputs before their calls. Retain raw lines only until the matching question
        // is known; unrelated tool outputs, questions and answers are never decoded into values.
        var outputs: [String: (at: Date, line: Data)] = [:]
        let decoder = JSONDecoder()
        var completeAt: Int64?
        var oldestOffset: Int64?
        let scan = reader.scan(descriptor: descriptor, from: start, size: size) { line in
            oldestOffset = line.offset
            if let completeAt, line.offset < completeAt - Self.extraBytesForOtherBuckets { return .stop }
            if tail.newestEventAt == nil, let at = CodexTime.lineTimestamp(line.bytes) {
                tail.newestEventAt = at
            }
            guard line.containsAny(Self.needles),
                  let record = try? decoder.decode(TailRecord.self, from: line.data),
                  let at = record.timestamp
            else { return .next }
            if let request = record.inputRequest,
               at > (tail.inputRequest?.at ?? .distantPast) {
                tail.inputRequest = .init(callID: request.callID, asynchronous: request.asynchronous, at: at)
            }
            if let callID = record.outputCallID, outputs[callID] == nil {
                outputs[callID] = (at, line.data)
            }
            if record.isUserMessage || record.kind == "turn_aborted" {
                if tail.inputAcknowledgedAt == nil { tail.inputAcknowledgedAt = at }
                if tail.inputBoundaryAt == nil { tail.inputBoundaryAt = at }
            }
            Self.add(record, at: at, to: &tail)
            if completeAt == nil, tail.hasEverything { completeAt = line.offset }
            return .next
        }
        if let request = tail.inputRequest, let output = outputs[request.callID], output.at >= request.at {
            if !request.asynchronous || (try? decoder.decode(InputAcknowledgement.self, from: output.line))?.accepted != true {
                tail.inputRequest?.resolvedAt = output.at
            }
        }
        // The oldest complete line is a safe boundary for another backwards scan. If the window held only
        // oversized lines, overlap by the maximum valid line length so a boundary cannot hide a valid event.
        let historyEnd = scan.reachedStart || scan.stopped ? nil
            : oldestOffset ?? max(start, size - Int64(max(1, reader.maxWindow - reader.maxLineLength)))
        return Result(tail: tail, scan: scan, historyEnd: historyEnd.flatMap { $0 > start ? $0 : nil })
    }

    /// Decoded only for the output matching an async question, never for arbitrary tool outputs.
    private struct InputAcknowledgement: Decodable {
        var accepted: Bool?
        init(from decoder: any Decoder) throws {
            let line = try decoder.container(keyedBy: AnyKey.self)
            guard let output = line.nested("payload")?.string("output"), output.utf8.count < 1_024,
                  let data = output.data(using: .utf8) else { return }
            struct Receipt: Decodable { var accepted: Bool? }
            accepted = (try? JSONDecoder().decode(Receipt.self, from: data))?.accepted
        }
    }

    /// Records `record` unless a newer line (visited earlier) already gave that value.
    private static func add(_ record: TailRecord, at: Date, to tail: inout RolloutTail) {
        switch record.kind {
        case "token_count":
            if record.hasInfo, tail.context == nil, let used = record.lastTotalTokens, used >= 0 {
                tail.context = .init(usedTokens: used, window: record.infoWindow.flatMap { $0 > 0 ? $0 : nil }, at: at)
            }
            switch record.rateLimits {
            case .none:
                break
            case .malformed:
                if tail.newestUnrecognizedAt == nil { tail.newestUnrecognizedAt = at }
            case .object(let raw):
                switch CodexLimits.decode(raw, at: at) {
                case .reading(let reading) where reading.windows.isEmpty:
                    // No numbers: an older reading of the bucket still counts, so keep looking for it.
                    if tail.newestEmptyAt == nil { tail.newestEmptyAt = at }
                case .reading(let reading):
                    if tail.readings[reading.bucketID] == nil { tail.readings[reading.bucketID] = reading }
                case .unrecognized:
                    if tail.newestUnrecognizedAt == nil { tail.newestUnrecognizedAt = at }
                }
            }
        case "task_started", "turn_started":
            if tail.inputBoundaryAt == nil { tail.inputBoundaryAt = at }
            if tail.lifecycle == nil { tail.lifecycle = .init(isStart: true, turnID: record.turnID, at: at) }
            if tail.startedWindow == nil, let window = record.startedWindow, window > 0 {
                tail.startedWindow = .init(value: window, at: at)
            }
        case "task_complete", "turn_complete", "turn_aborted":
            if tail.lifecycle == nil { tail.lifecycle = .init(isStart: false, turnID: record.turnID, at: at) }
        case "turn_context":
            if tail.turnContext == nil { tail.turnContext = .init(value: record.model, at: at) }
        case "thread_settings_applied":
            if tail.settingsModel == nil, let model = record.settingsModel {
                tail.settingsModel = .init(value: model, at: at)
            }
        default:
            break
        }
    }
}

/// Reads the head of a rollout once: 64 KB, grown to 1 MB until the first newline, then `session_meta`
/// (1.1 §3.3: the first line is 19–23 KB).
enum RolloutHeadReader {
    static let initialBytes = 64 * 1_024
    static let maxBytes = 1_024 * 1_024

    static func meta(descriptor: Int32) -> SessionMeta? {
        var count = initialBytes
        while true {
            guard let bytes = CodexFileAccess.readPrefix(descriptor, count: count) else { return nil }
            if let newline = bytes.firstIndex(of: 0x0A) {
                return (try? JSONDecoder().decode(SessionMetaLine.self, from: Data(bytes[..<newline])))?.meta
            }
            // The file ended (or shrank) before a newline: the first line isn't complete yet.
            guard bytes.count == count, count < maxBytes else { return nil }
            count = maxBytes
        }
    }
}
