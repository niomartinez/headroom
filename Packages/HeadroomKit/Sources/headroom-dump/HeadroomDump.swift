import CodexKit
import Foundation
import HeadroomModel
import HeadroomStore

/// `headroom-dump [--timing] [--watch N] [--names] [--claude-dir PATH] [--desktop-dir PATH] [--codex-dir PATH]`:
/// prints the live snapshot as pretty JSON (spec §4), read from the real `~/.claude` and
/// `~/Library/Application Support/Claude` without writing anything, then a `codex` section (1.1 §7) read from
/// `~/.codex`, read only: limits, plan, session counts per activity and issues.
///
/// - `--timing`: cold (first) and warm (cached) build durations on stderr, and the Codex read's.
/// - `--watch N`: afterwards rebuilds every 2 s, N times, printing moments as they happen (a one-line summary per
///   poll goes to stderr).
/// - `--names`: also print the Codex session names (never printed otherwise).
/// - `--claude-dir` / `--desktop-dir` / `--codex-dir`: read another `~/.claude`, Claude desktop or Codex folder
///   (end-to-end tests with a throwaway home).
enum HeadroomDump {
    struct Options: Equatable {
        var timing = false
        var watchCount = 0
        var names = false
        var claudeDirectory: String?
        var desktopDirectory: String?
        var codexDirectory: String?
    }

    static let usage =
        "usage: headroom-dump [--timing] [--watch N] [--names] [--claude-dir PATH] [--desktop-dir PATH] [--codex-dir PATH]"
    static let warmRuns = 20
    static let pollInterval: TimeInterval = 2

    static func parse(_ arguments: [String]) -> Options? {
        var options = Options()
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            switch argument {
            case "--timing":
                options.timing = true
            case "--names":
                options.names = true
            case "--watch":
                guard let text = remaining.popFirst(), let count = Int(text), count > 0 else { return nil }
                options.watchCount = count
            case "--claude-dir":
                guard let path = remaining.popFirst(), !path.isEmpty else { return nil }
                options.claudeDirectory = path
            case "--desktop-dir":
                guard let path = remaining.popFirst(), !path.isEmpty else { return nil }
                options.desktopDirectory = path
            case "--codex-dir":
                guard let path = remaining.popFirst(), !path.isEmpty else { return nil }
                options.codexDirectory = path
            default:
                return nil
            }
        }
        return options
    }

    static func run(arguments: [String]) -> Int32 {
        guard let options = parse(arguments) else {
            printError(usage)
            return 2
        }
        let access = AccessState(
            claudeDirectoryReadable: true,
            desktopDirectoryReadable: true,
            desktopAppInstalled: FileManager.default.fileExists(atPath: "/Applications/Claude.app")
        )
        var paths = ClaudePaths.standard()
        if let path = options.claudeDirectory {
            paths.claudeDirectory = URL(fileURLWithPath: path, isDirectory: true)
        }
        if let path = options.desktopDirectory {
            paths.desktopSupportDirectory = URL(fileURLWithPath: path, isDirectory: true)
        }
        let builder = SnapshotBuilder(paths: paths)

        let clock = ContinuousClock()
        var snapshot = HeadroomSnapshot.empty(at: Date())
        let cold = clock.measure { snapshot = builder.build(access: access, now: Date()) }
        // Taken now: the warm builds of `--timing` would replace it.
        var previous = (snapshot: snapshot, desktopAccount: builder.desktopAccount)
        guard let json = encode(snapshot) else {
            printError("headroom-dump: could not encode the snapshot")
            return 1
        }
        print(json)

        let codexHome = options.codexDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? CodexPaths.standard().codexDirectory
        // Processes only, like `SnapshotBuilder(paths:)`: the app adds its NSWorkspace check for the Codex app.
        let codexReader = CodexReader(codexHome: codexHome, runtime: CodexRuntimeProbe(appIsRunning: { false }))
        let codexNow = Date()
        var codexReading = CodexReading(usage: ToolUsage(tool: .codex, status: .noActivity), sessions: [], issues: [])
        let codexExists = FileManager.default.fileExists(atPath: codexHome.path)
        let codexCold = clock.measure { if codexExists { codexReading = codexReader.read(now: codexNow) } }
        let section = CodexSection(
            reading: codexReading, folderExists: codexExists, names: options.names, now: codexNow,
            codexRunning: CodexRuntimeProbe.codexProcessExists()
        )
        guard let codexJSON = encode(["codex": section]) else {
            printError("headroom-dump: could not encode the codex section")
            return 1
        }
        print(codexJSON)

        if options.timing {
            let warm = (0..<warmRuns).map { _ in clock.measure { _ = builder.build(access: access, now: Date()) } }.sorted()
            printError(
                "cold build: \(milliseconds(cold))\n"
                    + "warm build (\(warmRuns) runs): median \(milliseconds(warm[warm.count / 2])), "
                    + "min \(milliseconds(warm[0])), max \(milliseconds(warm[warm.count - 1]))"
            )
            if codexExists {
                // Polls 2 s apart, as the app's: no walk, only what changed.
                let polls = (1...warmRuns).map { run in
                    clock.measure { _ = codexReader.read(now: codexNow.addingTimeInterval(TimeInterval(run) * 0.1)) }
                }.sorted()
                printError(
                    "codex cold read: \(milliseconds(codexCold))\n"
                        + "codex poll (\(warmRuns) runs): median \(milliseconds(polls[polls.count / 2])), "
                        + "max \(milliseconds(polls[polls.count - 1]))"
                )
            }
        }

        for poll in 0..<options.watchCount {
            Thread.sleep(forTimeInterval: pollInterval)
            let now = Date()
            let current = (snapshot: builder.build(access: access, now: now), desktopAccount: builder.desktopAccount)
            let moments = MomentDetector.moments(
                previous: previous.snapshot, previousDesktopAccount: previous.desktopAccount,
                current: current.snapshot, currentDesktopAccount: current.desktopAccount
            )
            for moment in moments {
                print("\(timestamp(now)) \(describe(moment))")
            }
            printError("\(timestamp(now)) poll \(poll + 1)/\(options.watchCount): \(summary(current.snapshot))")
            previous = current
        }
        return 0
    }

    static func encode<Value: Encodable>(_ snapshot: Value) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func describe(_ moment: Moment) -> String {
        switch moment {
        case .sessionFinished(let id, let name): "sessionFinished \"\(name)\" (\(id))"
        case .sessionNeedsInput(let id, let name): "sessionNeedsInput \"\(name)\" (\(id))"
        case .limitCrossed(let kind, let percent): "limitCrossed \(kind.rawValue) \(percent)%"
        case .toolLimitCrossed(let tool, let window, let percent):
            "toolLimitCrossed \(tool.rawValue) \(window.title) \(percent)%"
        }
    }

    static func summary(_ snapshot: HeadroomSnapshot) -> String {
        func percent(_ reading: LimitReading?) -> String {
            guard let used = reading?.usedPercent else { return "–" }
            // A malformed file can hold any number (e.g. 1e300), and `Int(_:)` traps on one out of range.
            return Int(exactly: used.rounded()).map { "\($0)%" } ?? "\(used)%"
        }
        var parts = [
            "\(snapshot.sessions.count) sessions (\(snapshot.workingCount) working, \(snapshot.waitingCount) waiting)",
            "5h \(percent(snapshot.plan.fiveHour))",
            "wk \(percent(snapshot.plan.weekly))",
        ]
        if !snapshot.issues.isEmpty {
            parts.append("issues: \(snapshot.issues.map(\.rawValue).sorted().joined(separator: ", "))")
        }
        return parts.joined(separator: " · ")
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        let value = Double(seconds) * 1000 + Double(attoseconds) / 1e15
        return String(format: "%.2f ms", value)
    }

    private static func timestamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle())
    }

    private static func printError(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}
