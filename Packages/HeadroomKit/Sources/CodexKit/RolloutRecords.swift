import Foundation

// The only rollout fields CodexKit decodes (1.1 §3.2, §0.1 invariant 4: prompt text is never read into a
// value). Decoding is lenient: a field of an unexpected type reads as absent instead of failing the line.

/// A key-by-string coding key, for the lenient decoders below.
struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension KeyedDecodingContainer where Key == AnyKey {
    func string(_ key: String) -> String? {
        try? decodeIfPresent(String.self, forKey: AnyKey(key))
    }

    /// A JSON number, or a string holding one.
    func number(_ key: String) -> Double? {
        let key = AnyKey(key)
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let text = try? decodeIfPresent(String.self, forKey: key) { return Double(text) }
        return nil
    }

    /// A whole JSON number (`42` or `42.0`).
    func integer(_ key: String) -> Int? {
        guard let value = number(key), value.isFinite, value == value.rounded(), abs(value) < 1e15 else { return nil }
        return Int(value)
    }

    func nested(_ key: String) -> KeyedDecodingContainer<AnyKey>? {
        try? nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey(key))
    }

    /// Present with a JSON null.
    func isNull(_ key: String) -> Bool {
        let key = AnyKey(key)
        return contains(key) && ((try? decodeNil(forKey: key)) ?? false)
    }
}

/// The first line of a rollout: `session_meta` (1.1 §3.2).
struct SessionMeta: Sendable, Equatable {
    /// `source`: a name (`cli`, `vscode`, `exec`, `mcp`, …) or an object (a subagent).
    enum Source: Sendable, Equatable {
        case name(String)
        case object
        case missing
    }

    var id: String?
    var parentThreadID: String?
    var timestamp: Date?
    var cwd: String?
    var source: Source
    var threadSource: String?

    init(
        id: String?, parentThreadID: String? = nil, timestamp: Date?, cwd: String?, source: Source,
        threadSource: String?
    ) {
        self.id = id
        self.parentThreadID = parentThreadID
        self.timestamp = timestamp
        self.cwd = cwd
        self.source = source
        self.threadSource = threadSource
    }

    /// A root thread the user started in Codex (1.1 §3.5): `thread_source` "user", or, without one (older
    /// Codex), `source` "cli" or "vscode". Subagents, guardian reviews, `codex exec` (automation) and MCP threads
    /// are not.
    var isRootNativeThread: Bool {
        if parentThreadID != nil { return false }
        switch source {
        case .object: return false
        case .name(let name) where ["exec", "mcp"].contains(name.lowercased()): return false
        default: break
        }
        if let threadSource { return threadSource == "user" }
        if case .name(let name) = source { return ["cli", "vscode"].contains(name.lowercased()) }
        return false
    }

    /// `source "cli"`: the Codex CLI in a terminal; anything else is the Codex app or an editor (1.1 §3.5).
    var isTerminal: Bool {
        if case .name(let name) = source { return name.lowercased() == "cli" }
        return false
    }
}

/// `{"type":"session_meta","payload":{...}}`; nil `meta` for any other first line.
struct SessionMetaLine: Decodable {
    var meta: SessionMeta?

    init(from decoder: any Decoder) throws {
        let line = try decoder.container(keyedBy: AnyKey.self)
        guard line.string("type") == "session_meta", let payload = line.nested("payload") else {
            meta = nil
            return
        }
        let source: SessionMeta.Source
        if let name = payload.string("source") {
            source = .name(name)
        } else if payload.nested("source") != nil {
            source = .object
        } else {
            source = .missing
        }
        meta = SessionMeta(
            id: payload.string("id")?.lowercased(),
            parentThreadID: payload.string("parent_thread_id"),
            timestamp: payload.string("timestamp").flatMap(CodexTime.parse),
            cwd: payload.string("cwd"),
            source: source,
            threadSource: payload.string("thread_source")
        )
    }
}

/// A usage window as written: `{"used_percent":42.0,"window_minutes":10080,"resets_at":1790700000}`, or the
/// v0.46–0.49 form with `resets_in_seconds`.
struct RawWindow: Sendable, Equatable {
    var usedPercent: Double?
    var windowMinutes: Double?
    var resetsAt: Double?
    var resetsInSeconds: Double?
}

/// A `rate_limits` object as written (1.1 §3.2), every field optional.
struct RawRateLimits: Sendable, Equatable {
    /// A window slot: absent, null, an object, or something else (malformed).
    enum Slot: Sendable, Equatable {
        case absent
        case null
        case window(RawWindow)
        case malformed
    }

    var limitID: String?
    var limitName: String?
    var primary: Slot
    var secondary: Slot
    var planType: String?
    /// The ~v0.40 flat form.
    var primaryUsedPercent: Double?
    var secondaryUsedPercent: Double?
    var primaryWindowMinutes: Double?
    var secondaryWindowMinutes: Double?
    /// Whether any key of Codex's rate-limit snapshot is present, so an object without windows is a known empty
    /// bucket rather than an unknown shape.
    var hasSnapshotKeys: Bool

    init(
        limitID: String? = nil, limitName: String? = nil, primary: Slot = .absent, secondary: Slot = .absent,
        planType: String? = nil, primaryUsedPercent: Double? = nil, secondaryUsedPercent: Double? = nil,
        primaryWindowMinutes: Double? = nil, secondaryWindowMinutes: Double? = nil, hasSnapshotKeys: Bool = true
    ) {
        self.limitID = limitID
        self.limitName = limitName
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
        self.primaryUsedPercent = primaryUsedPercent
        self.secondaryUsedPercent = secondaryUsedPercent
        self.primaryWindowMinutes = primaryWindowMinutes
        self.secondaryWindowMinutes = secondaryWindowMinutes
        self.hasSnapshotKeys = hasSnapshotKeys
    }

    init(_ container: KeyedDecodingContainer<AnyKey>) {
        func slot(_ key: String) -> Slot {
            guard container.contains(AnyKey(key)) else { return .absent }
            if container.isNull(key) { return .null }
            guard let window = container.nested(key) else { return .malformed }
            return .window(RawWindow(
                usedPercent: window.number("used_percent"),
                windowMinutes: window.number("window_minutes"),
                resetsAt: window.number("resets_at"),
                resetsInSeconds: window.number("resets_in_seconds")
            ))
        }
        self.init(
            limitID: container.string("limit_id"),
            limitName: container.string("limit_name"),
            primary: slot("primary"),
            secondary: slot("secondary"),
            planType: container.string("plan_type"),
            primaryUsedPercent: container.number("primary_used_percent"),
            secondaryUsedPercent: container.number("secondary_used_percent"),
            primaryWindowMinutes: container.number("primary_window_minutes"),
            secondaryWindowMinutes: container.number("secondary_window_minutes"),
            hasSnapshotKeys: ["limit_id", "limit_name", "primary", "secondary", "credits", "plan_type"]
                .contains { container.contains(AnyKey($0)) }
        )
    }
}

/// One rollout line of the kinds the tail read looks at (1.1 §3.3), with only the fields it needs.
struct TailRecord: Decodable {
    enum RateLimits: Sendable, Equatable {
        /// `"rate_limits": null`, or no such key (API key, proxy, imported).
        case none
        case object(RawRateLimits)
        /// Not an object.
        case malformed
    }

    var timestamp: Date?
    /// `turn_context` or the `event_msg` payload type (`token_count`, `task_started`, …).
    var kind: String?
    var turnID: String?
    /// `turn_context.model`.
    var model: String?
    /// `task_started.model_context_window`.
    var startedWindow: Int?
    /// `token_count.info` is present (not null).
    var hasInfo = false
    /// `info.last_token_usage.total_tokens`: the context in use. Never `total_token_usage`, which is cumulative.
    var lastTotalTokens: Int?
    /// `info.model_context_window`.
    var infoWindow: Int?
    var rateLimits: RateLimits = .none
    /// `thread_settings_applied.thread_settings.model`.
    var settingsModel: String?
    /// Only the tool name and call id, never question arguments or message content.
    var inputRequest: (callID: String, asynchronous: Bool)?
    var outputCallID: String?
    var isUserMessage = false

    init(from decoder: any Decoder) throws {
        let line = try decoder.container(keyedBy: AnyKey.self)
        timestamp = line.string("timestamp").flatMap(CodexTime.parse)
        let type = line.string("type")
        guard let payload = line.nested("payload") else { return }
        switch type {
        case "response_item":
            switch payload.string("type") {
            case "function_call":
                let name = payload.string("name")?.split(separator: ".").last.map(String.init)
                if let name, ["request_user_input", "request_user_input_async"].contains(name),
                   let callID = payload.string("call_id"), !callID.isEmpty {
                    inputRequest = (callID, name == "request_user_input_async")
                }
            case "function_call_output":
                outputCallID = payload.string("call_id")
            case "message" where payload.string("role") == "user":
                // Desktop also writes environment and instruction context as user-role messages.
                // An actual user interaction acknowledges attention; its text is never decoded.
                let metadata = payload.nested("internal_chat_message_metadata_passthrough")
                let kinds = try? metadata?.decodeIfPresent([String].self, forKey: AnyKey("content_item_kinds"))
                isUserMessage = kinds.map { $0.contains("user.text") } ?? true
            default:
                break
            }
        case "turn_context":
            kind = "turn_context"
            turnID = payload.string("turn_id")
            model = payload.string("model")
        case "event_msg":
            kind = payload.string("type")
            turnID = payload.string("turn_id")
            switch kind {
            case "task_started", "turn_started":
                startedWindow = payload.integer("model_context_window")
            case "token_count":
                if let info = payload.nested("info") {
                    hasInfo = true
                    lastTotalTokens = info.nested("last_token_usage")?.integer("total_tokens")
                    infoWindow = info.integer("model_context_window")
                }
                if payload.contains(AnyKey("rate_limits")), !payload.isNull("rate_limits") {
                    rateLimits = payload.nested("rate_limits").map { .object(RawRateLimits($0)) } ?? .malformed
                }
            case "thread_settings_applied":
                settingsModel = payload.nested("thread_settings")?.string("model")
            default:
                break
            }
        default:
            break
        }
    }
}

/// A `session_index.jsonl` line: `{"id":…,"thread_name":…,"updated_at":…}`.
struct SessionIndexRecord: Decodable {
    var id: String?
    var threadName: String?

    init(from decoder: any Decoder) throws {
        let line = try decoder.container(keyedBy: AnyKey.self)
        id = line.string("id")?.lowercased()
        threadName = line.string("thread_name")
    }
}

/// `external_agent_session_imports.json`: `{"records":[{"imported_thread_id":…,"imported_at":…}]}`. Titles and
/// source paths are not decoded.
struct ImportsFile: Decodable {
    var imports: [String: Date] = [:]

    init(from decoder: any Decoder) throws {
        let file = try decoder.container(keyedBy: AnyKey.self)
        guard var records = try? file.nestedUnkeyedContainer(forKey: AnyKey("records")) else { return }
        while !records.isAtEnd {
            guard let record = try? records.nestedContainer(keyedBy: AnyKey.self) else {
                // Skip an element that isn't an object.
                _ = try? records.decode(IgnoredValue.self)
                continue
            }
            guard let id = record.string("imported_thread_id")?.lowercased() else { continue }
            // Epoch seconds; a 13-digit value is milliseconds.
            let at = record.number("imported_at").map { Date(timeIntervalSince1970: $0 >= 1e12 ? $0 / 1_000 : $0) }
            // The newest import of a thread wins; one without a time excludes it for good.
            let time = at ?? .distantFuture
            imports[id] = max(imports[id] ?? .distantPast, time)
        }
    }

    private struct IgnoredValue: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}
