import Foundation

/// One `~/.claude/sessions/<pid>.json` entry (spec §2.2).
public struct RegistryEntry: Sendable, Equatable {
    public var sessionId: String
    public var pid: Int32
    public var cwd: String?
    public var entrypoint: String?
    public var kind: String?
    public var status: String?
    public var name: String?
    public var startedAt: Date?
    public var statusUpdatedAt: Date?
    /// How Claude Code chose `name`: `"derived"` (made up from the folder, CLI ≥ 2.1.281), `"auto"`
    /// (generated title) or `"user"` (renamed); often missing.
    public var nameSource: String?
    /// When the session's process started (`procStart`, whole seconds), used to notice a reused pid.
    public var processStartedAt: Date?
    /// What a `waiting` session waits for (CLI ≥ 2.1.281): "permission prompt", "input needed", "sandbox request",
    /// "goal proposal", "dialog open". Undocumented; unknown values keep 1.0's meaning (1.1 §14.1).
    public var waitingFor: String?
    /// The Claude Code version that wrote the entry ("2.1.281").
    public var version: String?
    /// The Claude desktop app's own id for the session (`local_<uuid>`), which its `claude://` links take
    /// (1.1 §14.3). Undocumented.
    public var hostSessionId: String?

    public init(
        sessionId: String,
        pid: Int32,
        cwd: String?,
        entrypoint: String?,
        kind: String?,
        status: String?,
        name: String?,
        startedAt: Date?,
        statusUpdatedAt: Date?,
        nameSource: String? = nil,
        processStartedAt: Date? = nil,
        waitingFor: String? = nil,
        version: String? = nil,
        hostSessionId: String? = nil
    ) {
        self.sessionId = sessionId
        self.pid = pid
        self.cwd = cwd
        self.entrypoint = entrypoint
        self.kind = kind
        self.status = status
        self.name = name
        self.startedAt = startedAt
        self.statusUpdatedAt = statusUpdatedAt
        self.nameSource = nameSource
        self.processStartedAt = processStartedAt
        self.waitingFor = waitingFor
        self.version = version
        self.hostSessionId = hostSessionId
    }
}

extension RegistryEntry {
    /// `nil` unless the file has a session id and a valid pid. Times are epoch milliseconds, except
    /// `procStart` (`ps -o lstart` in UTC). Claude Code reads `procStartFt ?? procStart`; on macOS
    /// it writes `procStart`, so that comes first and a `procStartFt` counts only in the same form.
    init?(json: JSONObject) {
        guard let sessionId = json.string("sessionId"), let pid = json.pid("pid") else { return nil }
        self.init(
            sessionId: sessionId,
            pid: pid,
            cwd: json.string("cwd"),
            entrypoint: json.string("entrypoint"),
            kind: json.string("kind"),
            status: json.string("status"),
            name: json.string("name"),
            startedAt: json.date(epochMilliseconds: "startedAt"),
            statusUpdatedAt: json.date(epochMilliseconds: "statusUpdatedAt"),
            nameSource: json.string("nameSource"),
            processStartedAt: ProcessStart.parseLstart(json.string("procStart"))
                ?? ProcessStart.parseLstart(json.string("procStartFt")),
            waitingFor: json.string("waitingFor"),
            version: json.string("version"),
            hostSessionId: json.string("hostSessionId")
        )
    }
}
