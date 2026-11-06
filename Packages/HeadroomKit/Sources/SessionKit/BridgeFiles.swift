import Foundation

/// Fields both bridge files carry (spec §2.4, §2.5). `writtenAt` is the envelope `ts`, epoch seconds.
struct BridgeFileHeader {
    var sessionId: String?
    var writtenAt: Date?
    var pid: Int32?
    var cwd: String?
    var transcriptPath: String?

    func isNewer(than other: BridgeFileHeader) -> Bool {
        (writtenAt ?? .distantPast) > (other.writtenAt ?? .distantPast)
    }
}

protocol BridgeFile {
    var header: BridgeFileHeader { get }
}

/// `<id>.hook.json`: `{"v":1,"ts":…,"pid":…,"event":…,"session_id":…,"cwd":…,"transcript_path":…,"notification_type":…}`.
/// The bridge writes `""` for fields it could not find; those read as `nil`.
struct HookFile: BridgeFile {
    static let suffix = ".hook.json"

    var header: BridgeFileHeader
    var event: String?
    var notificationType: String?

    init(json: JSONObject) {
        header = BridgeFileHeader(
            sessionId: json.string("session_id"),
            writtenAt: json.date(epochSeconds: "ts"),
            pid: json.pid("pid"),
            cwd: json.string("cwd"),
            transcriptPath: json.string("transcript_path")
        )
        event = json.string("event")
        notificationType = json.string("notification_type")
    }
}

/// `<id>.statusline.json`: `{"v":1,"ts":…,"pid":…,"payload":<raw status line payload>}`.
struct StatusLineFile: BridgeFile {
    static let suffix = ".statusline.json"

    var header: BridgeFileHeader
    var contextWindowSize: Int?
    var contextUsedPercent: Double?
    var modelId: String?

    init(json: JSONObject) {
        let payload = json.object("payload")
        let contextWindow = payload?.object("context_window")
        header = BridgeFileHeader(
            sessionId: payload?.string("session_id"),
            writtenAt: json.date(epochSeconds: "ts"),
            pid: json.pid("pid"),
            cwd: payload?.string("cwd") ?? payload?.object("workspace")?.string("current_dir"),
            transcriptPath: payload?.string("transcript_path")
        )
        contextWindowSize = contextWindow?.integer("context_window_size")
        contextUsedPercent = contextWindow?.number("used_percentage")
        // `model` is `{"id":…,"display_name":…}` or a plain string (spec §2.4).
        modelId = payload?.object("model")?.string("id") ?? payload?.string("model")
    }
}

extension BridgeSessionRecord {
    /// Combines whichever of the two files exist. For fields both carry, the newer file wins
    /// and the older one fills gaps.
    init(sessionId: String, hook: HookFile?, statusLine: StatusLineFile?) {
        var headers = [hook?.header, statusLine?.header].compactMap { $0 }
        if headers.count == 2, headers[1].isNewer(than: headers[0]) { headers.swapAt(0, 1) }
        self.init(
            sessionId: sessionId,
            pid: headers.lazy.compactMap(\.pid).first,
            cwd: headers.lazy.compactMap(\.cwd).first,
            transcriptPath: headers.lazy.compactMap(\.transcriptPath).first,
            lastEvent: hook?.event,
            lastEventAt: hook?.header.writtenAt,
            notificationType: hook?.notificationType,
            statusLineAt: statusLine?.header.writtenAt,
            contextWindowSize: statusLine?.contextWindowSize,
            contextUsedPercent: statusLine?.contextUsedPercent,
            modelId: statusLine?.modelId
        )
    }
}
