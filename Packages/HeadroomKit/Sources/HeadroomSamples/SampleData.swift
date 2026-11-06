import Foundation
import HeadroomModel

/// Made-up snapshots: invented session names, folders under `/Users/me`, no real ids or prompt
/// text. They drive the app's sample data mode (App Review, demos), `headroom-render` and the App
/// Store screenshots, so none of those ever show what's on the Mac they run on.
///
/// Every date is relative to `now`: `SampleData.fixed` pins it for renders that must come out the
/// same every time, `SampleData(now: Date())` keeps relative times ("2m ago", "resets in 2 hr")
/// current in the running app.
public struct SampleData: Sendable {
    public let calendar: Calendar
    public let now: Date
    /// The next Sunday, 7 PM, after `now`.
    public let weeklyReset: Date
    public let fiveHourReset: Date

    public init(now: Date, calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
        self.now = now
        weeklyReset = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 19, minute: 0, weekday: 1),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(3 * 86_400)
        fiveHourReset = now.addingTimeInterval(2 * 3600 + 50 * 60)
    }

    /// Thursday 2026-09-24, 14:10 local time, so the renders read "resets Sun 7 PM" in any time zone.
    public static let fixed = SampleData(now: localDate(day: 24, hour: 14, minute: 10))

    public static func localDate(day: Int, hour: Int, minute: Int, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let components = DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 1_790_230_000)
    }

    // MARK: Plans

    /// Both limits as the Claude app reports them, observed `age` seconds before `now`.
    public func plan(
        weekly: Double,
        fiveHour: Double,
        age: TimeInterval = 120,
        estimated: Bool = false,
        extra: Double? = nil,
        source: ReadingSource = .desktopApp
    ) -> PlanUsage {
        let observedAt = now.addingTimeInterval(-age)
        return PlanUsage(
            fiveHour: LimitReading(
                kind: .fiveHour, usedPercent: fiveHour, resetsAt: fiveHourReset,
                resetIsEstimated: estimated, observedAt: observedAt, source: source
            ),
            weekly: LimitReading(
                kind: .weekly, usedPercent: weekly, resetsAt: weeklyReset,
                resetIsEstimated: estimated, observedAt: observedAt, source: source
            ),
            extraUsagePercent: extra
        )
    }

    // MARK: Sessions

    public func session(
        _ id: String,
        _ activity: SessionActivity,
        name: String,
        project: String?,
        origin: SessionOrigin = .desktop,
        used: Int? = nil,
        window: Int = 1_000_000,
        model: String = "claude-opus-5-5",
        windowIsAssumed: Bool = false,
        minutesAgo: Double = 1,
        tool: ToolID = .claude,
        baselineTokens: Int = 0
    ) -> SessionInfo {
        SessionInfo(
            id: id,
            name: name,
            projectPath: project,
            origin: origin,
            activity: activity,
            activitySince: now.addingTimeInterval(-minutesAgo * 60),
            startedAt: now.addingTimeInterval(-3 * 3600),
            pid: nil,
            transcriptPath: nil,
            context: used.map {
                ContextUsage(
                    usedTokens: $0, windowTokens: window, model: model, windowIsExact: false, observedAt: nil,
                    windowIsAssumed: windowIsAssumed, baselineTokens: baselineTokens
                )
            },
            tool: tool
        )
    }

    public var working: [SessionInfo] {
        [
            session("w1", .working, name: "Refactor invoice export", project: "/Users/me/code/ledger", used: 720_000),
            session("w2", .working, name: "Draft onboarding emails", project: "/Users/me/code/website",
                    used: 28_000, window: 200_000, model: "claude-haiku-4-5", minutesAgo: 3),
        ]
    }

    public var waitingTerminal: SessionInfo {
        session(
            "t1", .waitingForInput, name: "harbor", project: "/Users/me/code/harbor", origin: .terminal,
            used: 131_000, window: 200_000, model: "claude-sonnet-4-5"
        )
    }

    public var idle: [SessionInfo] {
        [
            session("i1", .idle, name: "Fix flaky upload test", project: "/Users/me/code/atlas", used: 850_000, minutesAgo: 4),
            session("i2", .idle, name: "Update pricing table", project: "/Users/me/code/website", used: 142_000, window: 200_000, minutesAgo: 9),
            session("i3", .idle, name: "Tidy CI workflow", project: "/Users/me/code/atlas", used: 290_000, minutesAgo: 15),
            session("i4", .idle, name: "Write release notes", project: "/Users/me/code/ledger", used: 120_000, minutesAgo: 40),
            session("i5", .idle, name: "Investigate memory spike",
                    project: "/Users/me/Library/Application Support/Claude/scratch-workspaces/a/b/scratch-1", used: 440_000, minutesAgo: 70),
            session("i6", .idle, name: "Rename settings keys", project: "/Users/me/code/harbor", used: 16_000, window: 200_000, minutesAgo: 95),
            session("i7", .idle, name: "Sketch API error copy", project: nil, minutesAgo: 180),
        ]
    }

    /// Exercises truncation of the name and project folder.
    public var longName: SessionInfo {
        session(
            "l1", .idle, name: "Investigate intermittent upload failures on slow networks",
            project: "/Users/me/code/customer-facing-dashboard", used: 604_000, minutesAgo: 30
        )
    }

    /// Names and folders that don't both fit: the folder must still show, shortened.
    public var crowdedRows: [SessionInfo] {
        [
            session("c1", .working, name: "Short", project: "/Users/me/code/customer-facing-dashboard-monorepo-with-extra-long-name",
                    used: 120_000),
            session("c2", .working, name: "Tidy CI workflow for release", project: "/Users/me/code/ledger", used: 290_000),
            session("c3", .idle, name: "Sketch billing export dialog", project: "/Users/me/code/billing-service-functions",
                    used: 604_000, minutesAgo: 5),
            // Same name, different folders: the folder is what tells them apart.
            session("c4", .idle, name: "Prototype dynamic island panel", project: "/Users/me/code/website", used: 88_000, minutesAgo: 8),
            session("c5", .idle, name: "Prototype dynamic island panel", project: "/Users/me/code/harbor", origin: .terminal,
                    used: 51_000, window: 200_000, minutesAgo: 12),
        ]
    }

    /// Models whose window size is only a guess next to known ones: a token count, no percent.
    public var assumedWindows: [SessionInfo] {
        [
            session("a1", .working, name: "Port legacy importer", project: "/Users/me/code/ledger", used: 168_000,
                    window: 200_000, model: "claude-opus-4-5", windowIsAssumed: true),
            session("a2", .working, name: "Draft onboarding emails", project: "/Users/me/code/website",
                    used: 168_000, window: 200_000, model: "claude-haiku-4-5", minutesAgo: 2),
            session("a3", .idle, name: "Check invoice rounding", project: "/Users/me/code/atlas", used: 9_400,
                    window: 200_000, model: "claude-sonnet-4-6", windowIsAssumed: true, minutesAgo: 6),
            session("a4", .idle, name: "Tidy CI workflow", project: "/Users/me/code/atlas", used: 290_000, minutesAgo: 15),
        ]
    }

    /// Session names far wider than their character count suggests.
    public static let wideNames = [
        "wide-latin": String(repeating: "W", count: 30),
        "cjk": "修复登录错误并更新文档以及测试用例和发布说明内容",
        "emoji": String(repeating: "🚀", count: 30),
    ]

    // MARK: Codex and Copilot (1.1 §6.5)

    /// The next Wednesday, 9 AM, after `now`: the sample Codex weekly reset.
    public var codexWeeklyReset: Date {
        calendar.nextDate(after: now, matching: DateComponents(hour: 9, minute: 0, weekday: 4), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(6 * 86_400)
    }

    /// The sample Codex 5-hour reset: in 1h 10m.
    public var codexFiveHourReset: Date { now.addingTimeInterval(70 * 60) }

    /// The first of next month at 00:00 UTC: GitHub's Copilot reset (1.1 §4.4).
    public var copilotReset: Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let month = utc.dateComponents([.year, .month], from: now)
        return utc.date(from: month).flatMap { utc.date(byAdding: .month, value: 1, to: $0) } ?? now.addingTimeInterval(30 * 86_400)
    }

    /// Codex limits observed `age` seconds before `now`: weekly only by default, as Codex reports them (Nio,
    /// 2026-10-02: Codex has no 5-hour limit). `fiveHour` adds one, for scenes that check the two-ring path.
    public func codex(
        weekly: Double = 94, fiveHour: Double? = nil, age: TimeInterval = 300, otherBuckets: [NamedLimits] = []
    ) -> ToolUsage {
        let observedAt = now.addingTimeInterval(-age)
        var limits = [ToolLimit(window: .weekly, usedPercent: weekly, resetsAt: codexWeeklyReset, observedAt: observedAt)]
        if let fiveHour {
            limits.append(ToolLimit(window: .fiveHour, usedPercent: fiveHour, resetsAt: codexFiveHourReset, observedAt: observedAt))
        }
        return ToolUsage(
            tool: .codex, limits: limits, hasFiveHourWindow: fiveHour != nil, otherBuckets: otherBuckets, status: .ok,
            planName: "Plus"
        )
    }

    /// Codex tracked with no limits to show: `.noActivity` ("No Codex limits found"), `.needsAccess`, `.unrecognized`.
    public func codex(status: ToolStatus) -> ToolUsage {
        ToolUsage(tool: .codex, status: status)
    }

    /// A made-up Spark bucket at `weekly` percent (1.1 §3.4), for the gray line under the Codex row.
    public func codexSparkBucket(weekly: Double = 80, age: TimeInterval = 300) -> NamedLimits {
        let observedAt = now.addingTimeInterval(-age)
        return NamedLimits(id: "codex_bengalfox", name: "GPT-5.3-Codex-Spark", limits: [
            ToolLimit(window: .weekly, usedPercent: weekly, resetsAt: codexWeeklyReset, observedAt: observedAt),
        ])
    }

    /// Copilot usage: Pro, 512 of 1,500 credits by default, account "octocat"; `allowance` nil = the plan is "Not
    /// sure" (no percent).
    /// Statuses without a reading (`.notConnected`, `.signInExpired`, `.noIndividualUsage`) have no limits;
    /// `.offline` and `.rateLimited` keep the reading.
    public func copilot(
        used: Double = 512, allowance: Double? = 1500, extra: Double? = nil, status: ToolStatus = .ok,
        age: TimeInterval = 600, unit: UsageUnit = .aiCredits, planName: String = "Pro"
    ) -> ToolUsage {
        let hasReading = [.ok, .offline, .rateLimited].contains(status)
        let limits = hasReading ? [ToolLimit(
            window: .monthly, usedPercent: allowance.map { used / $0 * 100 }, used: used, allowance: allowance,
            extra: extra, unit: unit, resetsAt: copilotReset, observedAt: now.addingTimeInterval(-age)
        )] : []
        let connected = status != .notConnected
        return ToolUsage(
            tool: .copilot, limits: limits, status: status, planName: connected && allowance != nil ? planName : nil,
            account: connected ? "octocat" : nil
        )
    }

    /// The sample Codex session: "website" in the Codex app, working, context 41 % (Codex's own formula, with its
    /// 12,000-token baseline).
    public var codexSession: SessionInfo {
        session(
            "codex:01a0beba-55ec-7ac1-84a7-16d9f0a456e0", .working, name: "website", project: "/Users/me/code/website",
            used: 113_000, window: 258_400, model: "gpt-6-astra", minutesAgo: 2, tool: .codex, baselineTokens: 12_000
        )
    }

    /// A Codex CLI session, idle, in a terminal.
    public var codexTerminalSession: SessionInfo {
        session(
            "codex:01a0bec2-7d31-7aa0-9b1e-5f2c8d4e6a10", .idle, name: "atlas", project: "/Users/me/code/atlas",
            origin: .terminal, used: 64_000, window: 258_400, model: "gpt-6-astra", minutesAgo: 11, tool: .codex,
            baselineTokens: 12_000
        )
    }

    /// A Copilot CLI session that needs you (no context bar in 1.1, §4.9).
    public var copilotSession: SessionInfo {
        session(
            "copilot:5f0c7c1e-2b1d-4c3e-9a55-3c1f1b0e8d42", .waitingForInput, name: "billing", project: "/Users/me/code/billing",
            origin: .terminal, minutesAgo: 4, tool: .copilot
        )
    }

    // MARK: Snapshots

    public func snapshot(
        _ plan: PlanUsage,
        _ sessions: [SessionInfo] = [],
        issues: Set<DataIssue> = [],
        connected: Bool = true
    ) -> HeadroomSnapshot {
        HeadroomSnapshot(plan: plan, sessions: sessions, terminalBridgeConnected: connected, issues: issues, generatedAt: now)
    }

    public var full: HeadroomSnapshot {
        snapshot(plan(weekly: 89, fiveHour: 14), working + [waitingTerminal] + idle)
    }

    /// What the app shows in sample data mode, so App Review sees every feature (1.1 §6.5): sessions in every
    /// state (two working, a terminal session that needs you, idle ones behind "Show N more") with a Codex session,
    /// a Claude weekly limit past the 75 % warning (the pill shows its number), Codex (Plus, 5-hour 20 %, weekly
    /// 94 %, resets Wed 9 AM) and Copilot (Pro, 512 of 1,500 credits). `terminalConnected` keeps the panel's
    /// Connect / Disconnect terminal item true to the real bridge.
    public func showcase(terminalConnected: Bool) -> HeadroomSnapshot {
        var snapshot = claudeOnlyShowcase(terminalConnected: terminalConnected)
        snapshot.sessions = (snapshot.sessions + [codexSession]).sortedForDisplay()
        snapshot.codex = codex()
        snapshot.copilot = copilot()
        return snapshot
    }

    /// 1.0's sample data: Claude only. Keeps the 1.0 renders and store screenshots reproducible.
    public func claudeOnlyShowcase(terminalConnected: Bool) -> HeadroomSnapshot {
        snapshot(
            plan(weekly: 81, fiveHour: 34),
            (working + [waitingTerminal] + Array(idle.prefix(5))).sortedForDisplay(),
            connected: terminalConnected
        )
    }

    /// Claude, Codex and Copilot with sessions of all three, for the multi-tool renders: Claude weekly 89 % /
    /// 5-hour 14 %, Codex Plus 94 % / 20 %, Copilot Pro 512 of 1,500 credits.
    public var multiTool: HeadroomSnapshot {
        var snapshot = self.snapshot(
            plan(weekly: 89, fiveHour: 14),
            ([working[0], codexSession, waitingTerminal, copilotSession] + Array(idle.prefix(2)) + [codexTerminalSession])
                .sortedForDisplay()
        )
        snapshot.codex = codex()
        snapshot.copilot = copilot()
        return snapshot
    }

    /// Only `codex` and `copilot` tracked (Claude not), with `sessions`.
    public func withoutClaude(codex: ToolUsage? = nil, copilot: ToolUsage? = nil, _ sessions: [SessionInfo] = []) -> HeadroomSnapshot {
        var snapshot = self.snapshot(.empty, sessions.sortedForDisplay(), connected: false)
        snapshot.claudeTracked = false
        snapshot.codex = codex
        snapshot.copilot = copilot
        return snapshot
    }
}
