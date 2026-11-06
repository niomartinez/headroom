import Foundation
import Testing
@testable import SetupKit

/// A throwaway directory tree: `home/` plays the user's home, `scratch/` holds test-only files
/// (stdin payloads, helper scripts) so they never show up in snapshots of `home/`.
/// The home path contains a space so every script test also checks quoting.
final class Sandbox: Sendable {
    let root: URL
    let home: URL
    let scratch: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-setupkit-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home dir", isDirectory: true)
        scratch = root.appendingPathComponent("scratch", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var claude: URL { home.appendingPathComponent(".claude", isDirectory: true) }
    var settings: URL { claude.appendingPathComponent("settings.json") }
    var backup: URL { claude.appendingPathComponent("settings.json.headroom-backup") }
    var bridgeDirectory: URL { claude.appendingPathComponent("headroom", isDirectory: true) }
    var script: URL { bridgeDirectory.appendingPathComponent("bridge.sh") }
    var originalStatusLine: URL { bridgeDirectory.appendingPathComponent("original-statusline.json") }
    var statusLineLatest: URL { bridgeDirectory.appendingPathComponent("statusline-latest.json") }
    var sessions: URL { bridgeDirectory.appendingPathComponent("sessions", isDirectory: true) }
    var installer: BridgeInstaller { BridgeInstaller(claudeDirectory: claude) }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func writeSettings(_ text: String) throws { try write(text, to: settings) }

    func settingsObject() throws -> [String: Any] {
        try #require(try jsonObject(at: settings) as? [String: Any])
    }

    /// Writes the current bridge script where the installer would put it.
    func placeScript() throws {
        try write(BridgeScript.contents, to: script)
    }

    /// The saved status line command the bridge chains, byte for byte.
    var originalStatusLineCommand: URL { bridgeDirectory.appendingPathComponent("original-statusline.cmd") }

    /// The app bundle path "Connect terminal" records (bridge version 4).
    var appPath: URL { bridgeDirectory.appendingPathComponent("app-path") }
    /// The App Store version's container in the sandbox home.
    var container: URL { home.appendingPathComponent("Library/Containers/com.niomartinez.headroom", isDirectory: true) }
    /// Stands in for /Applications/Headroom.app in scripts from `placeScriptCheckingSandboxApplications()`.
    var applicationsCopy: URL { scratch.appendingPathComponent("Applications/Headroom.app", isDirectory: true) }

    /// Writes the bridge script (over an installed one too) with its /Applications/Headroom.app check
    /// pointed at `applicationsCopy`: whether the real one exists depends on the machine running the tests.
    func placeScriptCheckingSandboxApplications() throws {
        let contents = BridgeScript.contents
        try #require(contents.contains("\"\(BridgeScript.applicationsCopyPath)\""))
        try write(contents.replacingOccurrences(of: BridgeScript.applicationsCopyPath, with: applicationsCopy.path), to: script)
    }

    /// Creates an empty directory at `url` (an app bundle or a container, as far as the bridge can tell).
    func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Saves `statusLine` the way "Connect terminal" does: as JSON (restored on Disconnect) and its
    /// command on its own (run by the bridge).
    func saveOriginalStatusLine(_ statusLine: [String: Any]) throws {
        try write(try jsonText(statusLine, pretty: true), to: originalStatusLine)
        if let command = statusLine["command"] as? String {
            try write(command, to: originalStatusLineCommand)
        }
    }

    /// Names directly inside `directory` that start with `prefix`, sorted.
    func entries(in directory: URL, prefix: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasPrefix(prefix) }.sorted()
    }

    /// Temp files (`.<name>.<pid>.tmp`) left in the bridge folder or its sessions folder.
    func bridgeTempFiles() -> [String] {
        [bridgeDirectory, sessions].flatMap { directory in
            entries(in: directory, prefix: ".").filter { $0.hasSuffix(".tmp") }
        }
    }

    /// Every path under `home/` with its contents (`nil` for directories).
    func snapshot() -> [String: Data?] {
        var result: [String: Data?] = [:]
        guard let walker = FileManager.default.enumerator(at: home, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return result
        }
        let prefix = home.resolvingSymlinksInPath().path
        for case let url as URL in walker {
            let path = String(url.resolvingSymlinksInPath().path.dropFirst(prefix.count))
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            result[path] = isDirectory ? .some(nil) : .some(try? Data(contentsOf: url))
        }
        return result
    }

    /// True when any file under `home/` contains `needle`.
    func anyFileContains(_ needle: String) -> Bool {
        snapshot().values.contains { data in
            guard let data else { return false }
            return data.range(of: Data(needle.utf8)) != nil
        }
    }
}

// MARK: - JSON

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func fixtureText(_ name: String) throws -> String {
    try #require(String(data: try fixture(name), encoding: .utf8))
}

func jsonObject(at url: URL) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(contentsOf: url), options: [.fragmentsAllowed])
}

func parseJSON(_ text: String) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
}

func jsonText(_ value: Any, pretty: Bool = false) throws -> String {
    var options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
    if pretty { options.insert(.prettyPrinted) }
    return String(decoding: try JSONSerialization.data(withJSONObject: value, options: options), as: UTF8.self)
}

/// Value equality of two JSON values (as parsed by JSONSerialization or written as literals).
func jsonEqual(_ a: Any?, _ b: Any?) -> Bool {
    switch (a, b) {
    case (nil, nil): true
    case let (a?, b?): (a as AnyObject).isEqual(b as AnyObject)
    default: false
    }
}

// MARK: - Running the bridge

struct BridgeRun {
    var stdout: String
    var status: Int32
    var seconds: Double
}

/// Runs `/bin/bash <script> <mode>` with `HOME` pointed at the sandbox and `stdin` as input.
@discardableResult
func runBridge(
    _ mode: String,
    stdin: String?,
    in sandbox: Sandbox,
    environment: [String: String] = [:]
) throws -> BridgeRun {
    if !sandbox.exists(sandbox.script) { try sandbox.placeScript() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [sandbox.script.path, mode]
    return try run(process, stdin: stdin, in: sandbox, environment: environment)
}

/// Runs an already configured process with the sandbox environment, capturing stdout.
func run(
    _ process: Process,
    stdin: String?,
    in sandbox: Sandbox,
    environment: [String: String] = [:],
    standardError: FileHandle = .nullDevice
) throws -> BridgeRun {
    var env = ["HOME": sandbox.home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
    env.merge(environment) { _, new in new }
    process.environment = env
    if let stdin {
        let input = sandbox.scratch.appendingPathComponent("stdin-\(UUID().uuidString)")
        try Data(stdin.utf8).write(to: input)
        process.standardInput = try FileHandle(forReadingFrom: input)
    } else {
        process.standardInput = FileHandle.nullDevice
    }
    let output = Pipe()
    process.standardOutput = output
    process.standardError = standardError
    let clock = ContinuousClock()
    let start = clock.now
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let elapsed = clock.now - start
    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    return BridgeRun(stdout: String(decoding: data, as: UTF8.self), status: process.terminationStatus, seconds: seconds)
}

/// Background threads that keep looking up `/dev/fd/0`, as concurrent bridge runs (hooks of
/// parallel tool calls, status line refreshes, other sessions) do. While they run, macOS
/// answers `stat("/dev/fd/N")` in any process with EBADF about one time in four.
final class DevFdProber {
    private let threads: [Thread]
    private let finished = DispatchGroup()

    init(threads count: Int) {
        var threads: [Thread] = []
        for _ in 0..<count {
            finished.enter()
            let thread = Thread { [finished] in
                var info = stat()
                while !Thread.current.isCancelled { _ = stat("/dev/fd/0", &info) }
                finished.leave()
            }
            threads.append(thread)
        }
        self.threads = threads
        threads.forEach { $0.start() }
    }

    func stop() {
        threads.forEach { $0.cancel() }
        finished.wait()
    }
}

/// Runs the bridge with its stdin and stderr closed (not /dev/null), killing it after 5 s.
func runBridgeWithClosedStdio(_ mode: String, in sandbox: Sandbox) throws -> BridgeRun {
    if !sandbox.exists(sandbox.script) { try sandbox.placeScript() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", #"exec /bin/bash "$0" "$1" <&- 2>&-"#, sandbox.script.path, mode]
    let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: watchdog)
    defer { watchdog.cancel() }
    return try run(process, stdin: nil, in: sandbox)
}

/// Runs `/bin/sh -c command` the way Claude Code runs a status line or hook command, capturing
/// stdout and stderr.
func runShellCommand(
    _ command: String,
    stdin: String?,
    in sandbox: Sandbox,
    environment: [String: String] = [:]
) throws -> (run: BridgeRun, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    let errors = sandbox.scratch.appendingPathComponent("stderr-\(UUID().uuidString)")
    FileManager.default.createFile(atPath: errors.path, contents: nil)
    let handle = try FileHandle(forWritingTo: errors)
    defer { try? handle.close() }
    let result = try run(process, stdin: stdin, in: sandbox, environment: environment, standardError: handle)
    return (result, try String(contentsOf: errors, encoding: .utf8))
}

// MARK: - Timing

/// A wall-clock bound that holds on a machine under heavy load (tests run in parallel, other builds
/// run beside them) yet still catches a real slowdown: the median of several runs must stay below
/// `median`, so one run delayed by a load spike doesn't fail it, and no run may take `ceiling` or
/// longer, so a hang or a pathological input still does.
struct TimingBound {
    var median: Double
    var ceiling: Double

    func check(_ seconds: [Double], _ label: String, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let slowest = seconds.max() else {
            Issue.record("\(label): no runs", sourceLocation: sourceLocation)
            return
        }
        let middle = medianOf(seconds)
        #expect(middle < median, "\(label): median \(middle) s of \(seconds)", sourceLocation: sourceLocation)
        #expect(slowest < ceiling, "\(label): slowest run \(slowest) s of \(seconds)", sourceLocation: sourceLocation)
    }
}

/// The middle value (the mean of the two middle ones for an even count); 0 for none.
func medianOf(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return 0 }
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
}

// MARK: - Special files

/// Creates a named pipe. Opening it for reading blocks until a writer shows up.
func makeFIFO(at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard mkfifo(url.path, 0o600) == 0 else {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
    }
}

private final class Box<T>: @unchecked Sendable {
    var value: T?
}

/// Runs `body` on its own thread and returns its result, or nil when it hasn't finished within
/// `seconds`. A thread stuck reading one of `fifos` is then released: the FIFOs are opened for
/// writing (and closed again) until it finishes, so it sees end-of-file.
func finishes<T: Sendable>(
    within seconds: Double,
    unblocking fifos: [URL],
    _ body: @escaping @Sendable () -> T
) -> T? {
    let box = Box<T>()
    let done = DispatchSemaphore(value: 0)
    Thread {
        box.value = body()
        done.signal()
    }.start()
    if done.wait(timeout: .now() + seconds) == .success { return box.value }
    let giveUp = Date().addingTimeInterval(10)
    while done.wait(timeout: .now() + 0.01) == .timedOut, Date() < giveUp {
        for fifo in fifos {
            let fd = open(fifo.path, O_WRONLY | O_NONBLOCK)
            if fd >= 0 { close(fd) }
        }
    }
    return nil
}

/// The error `body` throws, or nil.
func thrownError(_ body: () throws -> Void) -> BridgeInstallError? {
    do {
        try body()
        return nil
    } catch let error as BridgeInstallError {
        return error
    } catch {
        Issue.record("unexpected error \(error)")
        return nil
    }
}

// MARK: - Concurrent writers

/// Threads that keep writing files by path into `directories` (temp file, then rename), as bridge
/// runs still in flight do while "Disconnect terminal" deletes ~/.claude/headroom. Like the bridge,
/// they never create the directories themselves.
final class PathWriters: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private let finished = DispatchGroup()

    init(directories: [URL], threads: Int) {
        for thread in 0..<threads {
            finished.enter()
            Thread { [self] in
                var n = 0
                while !isStopped {
                    n += 1
                    for directory in directories {
                        let name = "writer-\(thread)-\(n % 16)"
                        let temp = directory.appendingPathComponent(".\(name).json.tmp").path
                        let fd = open(temp, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
                        guard fd >= 0 else { continue }
                        _ = write(fd, "{}\n", 3)
                        close(fd)
                        rename(temp, directory.appendingPathComponent("\(name).json").path)
                    }
                }
                finished.leave()
            }.start()
        }
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        finished.wait()
    }
}

/// The session record files the bridge wrote.
func hookRecord(_ sessionID: String, in sandbox: Sandbox) throws -> [String: Any] {
    try #require(try jsonObject(at: sandbox.sessions.appendingPathComponent("\(sessionID).hook.json")) as? [String: Any])
}

/// A hook payload as Claude Code sends it (compact, common fields first).
func hookPayload(
    event: String,
    sessionID: String = "0f5c2a7e-1b3d-4c5e-8f90-a1b2c3d4e5f6",
    cwd: String = "/Users/me/app",
    extra: String = ""
) throws -> String {
    let transcript = "/Users/me/.claude/projects/-Users-me-app/\(sessionID).jsonl"
    return "{\"session_id\":\(try jsonText(sessionID)),\"transcript_path\":\(try jsonText(transcript)),"
        + "\"cwd\":\(try jsonText(cwd)),\"permission_mode\":\"default\",\"hook_event_name\":\"\(event)\"\(extra)}"
}
