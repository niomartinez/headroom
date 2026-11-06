import CodexKit
import Foundation
import HeadroomModel
import SessionKit
@testable import HeadroomStore

/// A Codex folder reader whose reading the test sets. Counts its reads.
final class FakeCodexReader: CodexReadingProviding {
    let home: URL
    var reading: CodexReading
    private(set) var reads = 0

    init(home: URL, reading: CodexReading = FakeCodexReader.noActivity) {
        self.home = home
        self.reading = reading
    }

    func read(now: Date) -> CodexReading {
        reads += 1
        return reading
    }

    static let noActivity = CodexReading(usage: ToolUsage(tool: .codex, status: .noActivity), sessions: [], issues: [])
}

/// A Copilot CLI reader whose sessions the test sets. Counts its reads.
final class FakeCopilotCLIReader: CopilotSessionReading {
    let home: URL
    var sessions: [SessionInfo]
    private(set) var reads = 0

    init(home: URL, sessions: [SessionInfo] = []) {
        self.home = home
        self.sessions = sessions
    }

    func readSessions(now: Date) -> [SessionInfo] {
        reads += 1
        return sessions
    }
}

/// The fakes a `ToolFixture`'s builder made, one per granted folder, each preset with the current `codexReading`
/// and `copilotCLISessions`.
final class FakeToolReaders {
    private(set) var codex: [FakeCodexReader] = []
    private(set) var copilotCLI: [FakeCopilotCLIReader] = []
    /// What the next reads return. Setting either also updates the newest fake.
    var codexReading = FakeCodexReader.noActivity {
        didSet { codex.last?.reading = codexReading }
    }
    var copilotCLISessions: [SessionInfo] = [] {
        didSet { copilotCLI.last?.sessions = copilotCLISessions }
    }

    func makeCodex(_ home: URL) -> any CodexReadingProviding {
        let reader = FakeCodexReader(home: home, reading: codexReading)
        codex.append(reader)
        return reader
    }

    func makeCopilotCLI(_ home: URL) -> any CopilotSessionReading {
        let reader = FakeCopilotCLIReader(home: home, sessions: copilotCLISessions)
        copilotCLI.append(reader)
        return reader
    }
}

/// A `SnapshotBuilder` over a fixture tree whose Codex and Copilot CLI readers are fakes.
struct ToolFixture {
    let tree: FixtureTree
    let readers = FakeToolReaders()
    let builder: SnapshotBuilder

    init(probe: FakeProcessProbe = FakeProcessProbe()) throws {
        tree = try FixtureTree()
        builder = SnapshotBuilder(
            paths: tree.paths, probe: probe,
            codexReaders: readers.makeCodex, copilotCLIReaders: readers.makeCopilotCLI)
    }

    var codexHome: URL { tree.root.appendingPathComponent("codex", isDirectory: true) }
    var copilotCLIHome: URL { tree.root.appendingPathComponent("copilot", isDirectory: true) }

    /// Every tool tracked, every folder granted.
    var allSources: SourceSelection {
        SourceSelection(claude: true, codex: true, copilotCLI: true, codexHome: codexHome, copilotCLIHome: copilotCLIHome)
    }

    func build(
        access: AccessState = .everything, sources: SourceSelection? = nil, copilot: ToolUsage? = nil, now: Date
    ) -> HeadroomSnapshot {
        builder.build(access: access, sources: sources ?? allSources, copilot: copilot, now: now)
    }

    func remove() {
        tree.remove()
    }
}

extension AccessState {
    /// Every folder readable: Claude's, Codex's and Copilot CLI's.
    static let everything = AccessState(
        claudeDirectoryReadable: true, desktopDirectoryReadable: true, desktopAppInstalled: true,
        codexDirectoryReadable: true, codexInstalled: true, copilotDirectoryReadable: true, copilotCLIInstalled: true)
}

// MARK: - Synthetic tool data (made-up names and values)

func codexSession(
    _ thread: String, _ activity: SessionActivity, since: Date?, name: String = "ledger"
) -> SessionInfo {
    SessionInfo(
        id: "codex:\(thread)", name: name, projectPath: "/Users/tester/code/\(name)", origin: .desktop,
        activity: activity, activitySince: since, startedAt: testNow - hour, pid: nil, transcriptPath: nil,
        context: ContextUsage(
            usedTokens: 150_000, windowTokens: 258_400, model: "gpt-synthetic", windowIsExact: true,
            observedAt: since, baselineTokens: 12_000),
        tool: .codex)
}

func copilotCLISession(
    _ id: String, _ activity: SessionActivity, since: Date?, pid: Int32? = 4_242, name: String = "harbor"
) -> SessionInfo {
    SessionInfo(
        id: "copilot:\(id)", name: name, projectPath: "/Users/tester/code/\(name)", origin: .terminal,
        activity: activity, activitySince: since, startedAt: testNow - hour, pid: pid, transcriptPath: nil,
        context: nil, tool: .copilot)
}

func toolLimit(
    _ window: WindowKind, _ used: Double?, at observedAt: Date, resetsAt: Date? = nil,
    usedAmount: Double? = nil, allowance: Double? = nil, unit: UsageUnit? = nil
) -> ToolLimit {
    ToolLimit(
        window: window, usedPercent: used, used: usedAmount, allowance: allowance, unit: unit, resetsAt: resetsAt,
        observedAt: observedAt)
}

/// Codex on a synthetic Plus plan: weekly and 5-hour.
func codexUsage(
    weekly: Double?, fiveHour: Double? = nil, at observedAt: Date, plan: String? = "Plus",
    otherBuckets: [NamedLimits] = []
) -> ToolUsage {
    let limits = [
        weekly.map { toolLimit(.weekly, $0, at: observedAt, resetsAt: testNow + 72 * hour) },
        fiveHour.map { toolLimit(.fiveHour, $0, at: observedAt, resetsAt: testNow + 2 * hour) },
    ].compactMap { $0 }
    return ToolUsage(
        tool: .codex, limits: limits, hasFiveHourWindow: fiveHour != nil, otherBuckets: otherBuckets,
        status: limits.isEmpty ? .noActivity : .ok, planName: plan)
}

/// Copilot's monthly AI credits for `account`; a percent only with an allowance.
func copilotUsage(
    used: Double, allowance: Double?, at observedAt: Date, account: String? = "octo-tester", plan: String? = "Pro",
    resetsAt: Date = Date(timeIntervalSince1970: 1_790_812_800)
) -> ToolUsage {
    let limit = toolLimit(
        .monthly, allowance.map { used / $0 * 100 }, at: observedAt, resetsAt: resetsAt, usedAmount: used,
        allowance: allowance, unit: .aiCredits)
    return ToolUsage(tool: .copilot, limits: [limit], status: .ok, planName: plan, account: account)
}
