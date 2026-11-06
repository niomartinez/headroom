import Foundation
import HeadroomModel
@testable import CodexKit

/// The synthetic fixtures in `Fixtures/codex` (1.1 §11.1). Every value in them is made up.
enum CodexFixtures {
    static var directory: URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures/codex", isDirectory: true)
    }

    struct Entry: Decodable {
        var id: String
        var created: String
    }

    /// Fixture name → its thread id and creation time.
    static let ids: [String: Entry] = {
        let data = try! Data(contentsOf: directory.appendingPathComponent("ids.json"))
        return try! JSONDecoder().decode([String: Entry].self, from: data)
    }()

    static func threadID(_ name: String) -> String { ids[name]!.id }

    static func rollout(_ name: String) throws -> String {
        try String(contentsOf: directory.appendingPathComponent("rollouts/\(name).jsonl"), encoding: .utf8)
    }

    static func file(_ name: String) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }
}

/// A fixed runtime answer for the liveness table.
struct FixedRuntime: CodexRuntimeProbing {
    var running: Bool?
    func codexRunning() -> Bool? { running }
}

/// `2026-09-23T13:40:00Z`-style UTC dates.
func date(_ text: String) -> Date {
    CodexTime.parse(text)!
}

/// The time every reader test reads at unless it says otherwise: after all fixture events.
let testNow = date("2026-09-23T13:40:00Z")

/// A throwaway Codex folder with a `sessions/` subfolder, removed when released.
final class CodexHome {
    let root: URL
    let paths: CodexPaths

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexKitTests-\(UUID().uuidString)", isDirectory: true)
        paths = CodexPaths(codexDirectory: root)
        try FileManager.default.createDirectory(at: paths.sessionsDirectory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func reader(running: Bool? = true) -> CodexReader {
        let reader = CodexReader(codexHome: root, runtime: FixedRuntime(running: running))
        reader.calendar.timeZone = TimeZone(identifier: "UTC")!
        reader.locale = Locale(identifier: "en_US")
        return reader
    }

    /// Writes a fixture rollout as `sessions/2026/09/23/rollout-<ts>-<thread id>[_<rollout id>].jsonl`, dated like
    /// Codex leaves it: modified just after its last event (override with `modified`).
    @discardableResult
    func install(
        _ fixture: String, day: String = "2026/09/23", rolloutID: String? = nil, modified: Date? = nil
    ) throws -> URL {
        try installText(
            CodexFixtures.rollout(fixture), threadID: CodexFixtures.threadID(fixture), day: day, rolloutID: rolloutID,
            modified: modified
        )
    }

    /// Writes `text` as the rollout of `threadID`.
    @discardableResult
    func installText(
        _ text: String, threadID: String, day: String = "2026/09/23", rolloutID: String? = nil, modified: Date? = nil
    ) throws -> URL {
        let suffix = rolloutID.map { "_\($0)" } ?? ""
        let url = paths.sessionsDirectory
            .appendingPathComponent(day, isDirectory: true)
            .appendingPathComponent("rollout-2026-09-23T10-00-00-\(threadID)\(suffix).jsonl")
        try write(text, to: url)
        try setModified(url, modified ?? Self.lastEventTime(text).map { $0.addingTimeInterval(1) } ?? testNow)
        return url
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func append(_ text: String, to url: URL, modified: Date? = nil) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
        if let modified { try setModified(url, modified) }
    }

    func setModified(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    /// Creates `thread-writer-locks/` with a lock per id (and optionally Codex's `.coordination.lock`).
    func lock(_ threadIDs: [String], coordination: Bool = false) throws {
        try FileManager.default.createDirectory(at: paths.writerLocksDirectory, withIntermediateDirectories: true)
        for id in threadIDs {
            try Data().write(to: paths.writerLockFile(threadID: id))
        }
        if coordination {
            try Data().write(to: paths.writerLocksDirectory.appendingPathComponent(".coordination.lock"))
        }
    }

    func unlock(_ threadID: String) throws {
        try FileManager.default.removeItem(at: paths.writerLockFile(threadID: threadID))
    }

    func installSessionIndex(_ text: String) throws {
        try write(text, to: paths.sessionIndexFile)
    }

    func installImports(_ text: String) throws {
        try write(text, to: paths.importsFile)
    }

    /// The timestamp of the text's last line that has one.
    static func lastEventTime(_ text: String) -> Date? {
        text.split(separator: "\n").reversed().lazy.compactMap { CodexTime.lineTimestamp(Array($0.utf8)[...]) }.first
    }
}

/// Synthetic rollout lines for tests that build their own files.
enum RolloutText {
    static func meta(
        _ threadID: String, at: String, source: String = #""vscode""#, threadSource: String? = "user",
        cwd: String? = "/Users/me/code/app"
    ) -> String {
        var payload = #""id":"\#(threadID)","timestamp":"\#(at)","source":\#(source)"#
        if let threadSource { payload += #","thread_source":"\#(threadSource)""# }
        if let cwd { payload += #","cwd":"\#(cwd)""# }
        return #"{"timestamp":"\#(at)","type":"session_meta","payload":{\#(payload)}}"# + "\n"
    }

    static func tokenCount(at: String, rateLimits: String = "null", used: Int = 100_000, window: Int? = 258_400) -> String {
        let windowField = window.map { #","model_context_window":\#($0)"# } ?? ""
        return #"{"timestamp":"\#(at)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":9000000},"last_token_usage":{"total_tokens":\#(used)}\#(windowField)},"rate_limits":\#(rateLimits)}}"#
            + "\n"
    }

    static func weekly(_ percent: Double, resetsAt: Int = 1_790_700_000, plan: String = "pro") -> String {
        #"{"limit_id":"codex","limit_name":null,"primary":{"used_percent":\#(percent),"window_minutes":10080,"resets_at":\#(resetsAt)},"secondary":null,"plan_type":"\#(plan)"}"#
    }

    static func started(at: String, turn: String) -> String {
        #"{"timestamp":"\#(at)","type":"event_msg","payload":{"type":"task_started","turn_id":"\#(turn)"}}"# + "\n"
    }

    static func complete(at: String, turn: String) -> String {
        #"{"timestamp":"\#(at)","type":"event_msg","payload":{"type":"task_complete","turn_id":"\#(turn)"}}"# + "\n"
    }

    static func message(at: String, text: String) -> String {
        #"{"timestamp":"\#(at)","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"\#(text)"}]}}"#
            + "\n"
    }

    /// A made-up UUIDv7 thread id created at `created`.
    static func threadID(created: Date, salt: Int) -> String {
        let milliseconds = UInt64((created.timeIntervalSince1970 * 1_000).rounded())
        let hex = String(format: "%012llx", milliseconds) + String(format: "7%03lx8%03lx%012lx", salt % 4096, salt % 4096, salt)
        let chars = Array(hex)
        func part(_ range: Range<Int>) -> String { String(chars[range]) }
        return "\(part(0..<8))-\(part(8..<12))-\(part(12..<16))-\(part(16..<20))-\(part(20..<32))"
    }
}
