import Foundation
import HeadroomModel
import SessionKit

/// A fixed "now" for store tests: 2026-09-24 12:00:00 UTC.
let testNow = Date(timeIntervalSince1970: 1_790_251_200)

let second: TimeInterval = 1
let minute: TimeInterval = 60
let hour: TimeInterval = 3600

/// A `ProcessProbing` whose live pids, and when the processes holding them started, are fixed by the test.
struct FakeProcessProbe: ProcessProbing {
    var alive: Set<Int32>
    /// A live pid missing here has an unknown start time, which leaves liveness to `isAlive` alone.
    var startTimes: [Int32: Date]
    /// Pids running a command in a shell child (1.1 §14.11).
    var shells: Set<Int32>

    init(alive: Set<Int32> = [], startTimes: [Int32: Date] = [:], shells: Set<Int32> = []) {
        self.alive = alive
        self.startTimes = startTimes
        self.shells = shells
    }

    func isAlive(pid: Int32) -> Bool {
        alive.contains(pid)
    }

    func startTime(pid: Int32) -> Date? {
        alive.contains(pid) ? startTimes[pid] : nil
    }

    func shellParents() -> Set<Int32> {
        shells
    }
}

/// One desktop usage history sample for `FixtureTree.writeDesktopHistory`.
struct HistorySample {
    var time: Date
    var org = "org-a"
    var fiveHour: Double?
    var weekly: Double?
    var extra: Double?
}

/// A synthetic `~/.claude` and `~/Library/Application Support/Claude` in a fresh temp directory.
/// Every name, path and prompt in here is made up.
struct FixtureTree {
    let root: URL
    let paths: ClaudePaths

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeadroomStoreTests-\(UUID().uuidString)", isDirectory: true)
        paths = ClaudePaths(
            claudeDirectory: root.appendingPathComponent("claude", isDirectory: true),
            desktopSupportDirectory: root.appendingPathComponent("desktop", isDirectory: true)
        )
        try FileManager.default.createDirectory(at: paths.claudeDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.desktopSupportDirectory, withIntermediateDirectories: true)
    }

    func remove() {
        for directory in [paths.sessionsDirectory, paths.bridgeSessionsDirectory, root] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        }
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Writing files

    @discardableResult
    func write(_ text: String, to url: URL, modified: Date? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if let modified {
            try setModified(url, modified)
        }
        return url
    }

    func setModified(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    // MARK: - Desktop usage history (spec §2.1)

    @discardableResult
    func writeDesktopHistory(_ samples: [HistorySample], version: String = "2", modified: Date? = nil) throws -> URL {
        let items = samples.map { sample in
            let millis = Int64((sample.time.timeIntervalSince1970 * 1000).rounded())
            return #"{"t":\#(millis),"org":"\#(sample.org)","u":{"fh":\#(json(sample.fiveHour)),"sd":\#(json(sample.weekly)),"xu":\#(json(sample.extra))}}"#
        }
        let text = #"{"version":\#(version),"samples":[\#(items.joined(separator: ","))]}"#
        return try write(text, to: paths.planUsageHistoryFile, modified: modified)
    }

    // MARK: - Terminal status line (spec §2.4)

    /// `transcriptPath` goes into the payload's `transcript_path` when given.
    @discardableResult
    func writeStatusLineLatest(
        fiveHour: (used: Double, resetsAt: Date)?,
        weekly: (used: Double, resetsAt: Date)?,
        modified: Date,
        transcriptPath: String? = nil
    ) throws -> URL {
        var limits: [String] = []
        if let fiveHour {
            limits.append(#""five_hour":{"used_percentage":\#(fiveHour.used),"resets_at":\#(Int(fiveHour.resetsAt.timeIntervalSince1970))}"#)
        }
        if let weekly {
            limits.append(#""seven_day":{"used_percentage":\#(weekly.used),"resets_at":\#(Int(weekly.resetsAt.timeIntervalSince1970))}"#)
        }
        let transcript = transcriptPath.map { #""transcript_path":"\#($0)","# } ?? ""
        let text = #"{"session_id":"s-latest",\#(transcript)"model":{"id":"claude-haiku-4-5"},"rate_limits":{\#(limits.joined(separator: ","))}}"#
        return try write(text, to: paths.statusLineLatestFile, modified: modified)
    }

    // MARK: - Session registry (spec §2.2)

    /// `procStart`, when given, is written as Claude Code writes it (`ps -o lstart` in UTC); `nameSource` is
    /// written when given.
    @discardableResult
    func writeRegistryEntry(
        sessionId: String,
        pid: Int32,
        entrypoint: String = "claude-desktop",
        status: String = "idle",
        name: String? = "Polish onboarding copy",
        nameSource: String? = nil,
        cwd: String = "/Users/tester/code/sample-app",
        startedAt: Date = testNow - 2 * hour,
        statusUpdatedAt: Date = testNow - 10 * minute,
        procStart: Date? = nil
    ) throws -> URL {
        let nameField = name.map { #","name":"\#($0)""# } ?? ""
        let nameSourceField = nameSource.map { #","nameSource":"\#($0)""# } ?? ""
        let procStartField = procStart.map { #","procStart":"\#(lstart($0))""# } ?? ""
        let text = #"{"pid":\#(pid),"sessionId":"\#(sessionId)","cwd":"\#(cwd)","entrypoint":"\#(entrypoint)","kind":"interactive"\#(nameField)\#(nameSourceField),"status":"\#(status)","startedAt":\#(millis(startedAt)),"statusUpdatedAt":\#(millis(statusUpdatedAt)),"updatedAt":\#(millis(statusUpdatedAt)),"version":"2.1.280"\#(procStartField)}"#
        return try write(text, to: paths.sessionsDirectory.appendingPathComponent("\(pid).json"))
    }

    // MARK: - Transcripts (spec §2.3)

    /// `projects/<encoded cwd>/<sessionId>.jsonl` with one user line and one assistant line per usage.
    @discardableResult
    func writeTranscript(
        sessionId: String,
        projectFolder: String = "-Users-tester-code-sample-app",
        usages: [(model: String, tokens: Int, timestamp: Date)]
    ) throws -> URL {
        var lines = [#"{"type":"user","message":{"role":"user","content":"synthetic prompt"}}"#]
        for usage in usages {
            let input = usage.tokens / 2
            let cacheRead = usage.tokens - input - 100
            lines.append(
                #"{"type":"assistant","isSidechain":false,"timestamp":"\#(iso(usage.timestamp))","message":{"model":"\#(usage.model)","usage":{"input_tokens":\#(input),"cache_creation_input_tokens":0,"cache_read_input_tokens":\#(cacheRead),"output_tokens":100}}}"#
            )
        }
        let url = paths.projectsDirectory
            .appendingPathComponent(projectFolder, isDirectory: true)
            .appendingPathComponent("\(sessionId).jsonl")
        return try write(lines.joined(separator: "\n") + "\n", to: url)
    }

    // MARK: - Bridge session files (spec §2.4, §2.5)

    @discardableResult
    func writeBridgeHook(
        sessionId: String,
        pid: Int32?,
        event: String,
        at time: Date,
        cwd: String = "/Users/tester/code/terminal-tool",
        transcriptPath: String = ""
    ) throws -> URL {
        let text = #"{"v":1,"ts":\#(Int(time.timeIntervalSince1970)),"pid":\#(pid.map(String.init) ?? "null"),"event":"\#(event)","session_id":"\#(sessionId)","cwd":"\#(cwd)","transcript_path":"\#(transcriptPath)","notification_type":""}"#
        return try write(text, to: paths.bridgeSessionsDirectory.appendingPathComponent("\(sessionId).hook.json"))
    }

    @discardableResult
    func writeBridgeStatusLine(
        sessionId: String,
        pid: Int32?,
        at time: Date,
        model: String,
        contextWindowSize: Int,
        cwd: String = "/Users/tester/code/terminal-tool",
        transcriptPath: String = ""
    ) throws -> URL {
        let payload = #"{"session_id":"\#(sessionId)","transcript_path":"\#(transcriptPath)","cwd":"\#(cwd)","model":{"id":"\#(model)","display_name":"Synthetic"},"context_window":{"used_percentage":10,"context_window_size":\#(contextWindowSize)}}"#
        let text = #"{"v":1,"ts":\#(Int(time.timeIntervalSince1970)),"pid":\#(pid.map(String.init) ?? "null"),"payload":\#(payload)}"#
        return try write(text, to: paths.bridgeSessionsDirectory.appendingPathComponent("\(sessionId).statusline.json"))
    }
}

private func json(_ value: Double?) -> String {
    value.map { String($0) } ?? "null"
}

private func millis(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
}

private func iso(_ date: Date) -> String {
    date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
}

/// `LC_ALL=C TZ=UTC ps -o lstart=`: "Thu Sep 24 10:06:01 2026", "Thu Sep  3 16:27:07 2026".
func lstart(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
    let text = formatter.string(from: date)
    // `%e` pads a one-digit day with a space.
    let fields = text.split(separator: " ", omittingEmptySubsequences: false)
    guard fields.count == 5, fields[2].count == 1 else { return text }
    return "\(fields[0]) \(fields[1])  \(fields[2]) \(fields[3]) \(fields[4])"
}
