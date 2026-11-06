#if HEADROOM_COPILOT_CLI
import CoreFoundation
import Foundation
import HeadroomModel

/// One `headroom/sessions/<sessionId>.hook.json` written by the Copilot bridge (1.1 §4.9):
///
///     {"v":1,"ts":1790250200,"event":"notification","session_id":"<uuid>","cwd":"/Users/me/app",
///      "notification_type":"permission_prompt","pids":[[12345,"copilot"]]}
///
/// The bridge writes `""` for fields it could not find; those read as nil. The file is untrusted: anything of the
/// wrong type reads as nil too.
struct CopilotSessionRecord: Sendable, Equatable {
    /// One of the bridge's ancestors: `[pid, "name"]`, nearest first.
    struct Ancestor: Sendable, Equatable {
        var pid: Int32
        var name: String

        init(pid: Int32, name: String) {
            self.pid = pid
            self.name = name
        }
    }

    var sessionId: String
    /// The envelope `ts`: when the bridge wrote the record (whole seconds).
    var writtenAt: Date?
    /// Copilot CLI's hook event: `sessionStart`, `userPromptSubmitted`, `postToolUse`, `notification`, `agentStop`,
    /// `errorOccurred`, or `sessionCompleted` after a successful sessionEnd. Other sessionEnd reasons delete it.
    var event: String?
    var cwd: String?
    var notificationType: String?
    var ancestors: [Ancestor]

    init(
        sessionId: String,
        writtenAt: Date? = nil,
        event: String? = nil,
        cwd: String? = nil,
        notificationType: String? = nil,
        ancestors: [Ancestor] = []
    ) {
        self.sessionId = sessionId
        self.writtenAt = writtenAt
        self.event = event
        self.cwd = cwd
        self.notificationType = notificationType
        self.ancestors = ancestors
    }

    static let fileSuffix = ".hook.json"
    /// Records are a few hundred bytes; anything past this isn't one.
    static let maxFileBytes = 64 * 1024

    /// Parses a regular file of at most `maxFileBytes`. FIFOs, sockets, directories and symlinks are refused
    /// without opening them, so a stray special file can never block the reader. `fallbackId` (the file name's
    /// stem) is used when the record names no session.
    init?(contentsOf url: URL, fallbackId: String) {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maxFileBytes + 1), data.count <= Self.maxFileBytes else {
            return nil
        }
        self.init(data: data, fallbackId: fallbackId)
    }

    init?(data: Data, fallbackId: String) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionId = Self.sessionId(Self.string(json["session_id"]) ?? fallbackId)
        else { return nil }
        self.init(
            sessionId: sessionId,
            writtenAt: Self.number(json["ts"]).map { Date(timeIntervalSince1970: $0) },
            event: Self.string(json["event"]),
            cwd: Self.string(json["cwd"]),
            notificationType: Self.string(json["notification_type"]),
            ancestors: (json["pids"] as? [Any] ?? []).compactMap(Self.ancestor)
        )
    }

    /// `id` when it is a plain session id (what the bridge accepts as a file name), else nil.
    static func sessionId(_ id: String) -> String? {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        guard !id.isEmpty, id.count <= 128, id != ".", id != "..", id.allSatisfy(allowed.contains) else { return nil }
        return id
    }

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return value
    }

    /// A finite number; JSON booleans are not numbers here.
    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else {
            return nil
        }
        return value.doubleValue
    }

    /// `[pid, "name"]` with a positive pid that fits a `pid_t`.
    private static func ancestor(_ value: Any) -> Ancestor? {
        guard let pair = value as? [Any], pair.count >= 2, let number = number(pair[0]),
              let pid = Int32(exactly: number), pid > 0
        else { return nil }
        return Ancestor(pid: pid, name: pair[1] as? String ?? "")
    }

    /// 1.1 §4.9, §14.1: `userPromptSubmitted`, `postToolUse` → working; a `notification` of a needs-you type
    /// (`permission_prompt`, `elicitation_dialog`, `elicitation_url_dialog`, `agent_needs_input`, as for Claude
    /// Code) → waitingForInput, and `elicitation_complete`/`elicitation_response` → working; any other notification
    /// (including one without a type: Copilot CLI always sends it), `agentStop`, `sessionStart`, `errorOccurred`
    /// (a turn that failed) and anything unknown → idle.
    var activity: SessionActivity {
        switch event {
        case "userPromptSubmitted", "postToolUse":
            .working
        case "notification":
            if Self.waitingNotificationTypes.contains(notificationType ?? "") {
                .waitingForInput
            } else if ActivityMapping.resumedNotificationTypes.contains(notificationType ?? "") {
                .working
            } else {
                .idle
            }
        default:
            .idle
        }
    }

    /// The same needs-you types as Claude Code's bridge (1.1 §14.1).
    static let waitingNotificationTypes: Set<String> = ActivityMapping.needsYouNotificationTypes
    static let sessionEndEvent = "sessionEnd"
    static let sessionCompletedEvent = "sessionCompleted"
}
#endif
