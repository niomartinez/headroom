import Foundation
import HeadroomModel
import os
import SessionKit
import Testing

/// Where a click on a session row goes (1.1 §14.3), against a made-up process table and set of running apps.
@Suite struct SessionTargetTests {
    /// A process table from a list of entries, with working directories by pid.
    private struct FakeTable: ProcessTableReading {
        var entries: [ProcessEntry]
        var directories: [Int32: String] = [:]
        var listable = true

        func entry(pid: Int32) -> ProcessEntry? { entries.first { $0.pid == pid } }
        func all() -> [ProcessEntry]? { listable ? entries : nil }
        func workingDirectory(pid: Int32) -> String? { directories[pid] }
    }

    private static let terminal = HostApp(
        pid: 400, bundleIdentifier: "com.apple.Terminal", name: "Terminal",
        bundleURL: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), isRegular: true
    )
    private static let iTerm = HostApp(
        pid: 410, bundleIdentifier: HostAppNames.iTermBundleIdentifier, name: "iTerm",
        bundleURL: URL(fileURLWithPath: "/Applications/iTerm.app"), isRegular: true
    )
    private static let claude = HostApp(
        pid: 500, bundleIdentifier: ClaudeDesktopApp.bundleIdentifier, name: "Claude",
        bundleURL: URL(fileURLWithPath: "/Applications/Claude.app"), isRegular: true
    )
    /// The Claude app's helper, which hosts its terminal panel: not a Dock app.
    private static let claudeHelper = HostApp(
        pid: 510, bundleIdentifier: "com.anthropic.claudefordesktop.helper", name: "Claude Helper", bundleURL: nil,
        isRegular: false
    )
    private static let codexApp = HostApp(
        pid: 600, bundleIdentifier: CodexApp.bundleIdentifier, name: "ChatGPT",
        bundleURL: URL(fileURLWithPath: "/Applications/ChatGPT.app"), isRegular: true
    )
    private static let menuBarAgent = HostApp(
        pid: 700, bundleIdentifier: "com.example.agent", name: "Agent", bundleURL: nil, isRegular: false
    )

    private static let apps = [terminal, iTerm, claude, claudeHelper, codexApp, menuBarAgent]

    private func resolver(
        _ table: FakeTable,
        apps: [HostApp] = SessionTargetTests.apps,
        handlers: [String: String] = ["claude": "Claude", "codex": "ChatGPT"]
    ) -> SessionTargetResolver {
        SessionTargetResolver(
            processes: table,
            appForPID: { pid in apps.first { $0.pid == pid } },
            runningApp: { id in apps.first { $0.bundleIdentifier == id } },
            handlerName: { url in url.scheme.flatMap { handlers[$0] } }
        )
    }

    private func session(
        _ id: String, tool: ToolID = .claude, origin: SessionOrigin, pid: Int32? = nil, desktopSessionID: String? = nil,
        projectPath: String? = nil
    ) -> SessionInfo {
        SessionInfo(
            id: id, name: "Session", projectPath: projectPath, origin: origin, activity: .working, activitySince: nil,
            startedAt: nil, pid: pid, transcriptPath: nil, context: nil, tool: tool, desktopSessionID: desktopSessionID
        )
    }

    // MARK: Links

    @Test func aClaudeDesktopIdGivesTheContinueLink() {
        let url = SessionLinks.claudeDesktop(sessionID: "local_0f0e0d0c-1111-4222-8333-444455556666")
        #expect(url?.absoluteString == "claude://code/continue?session=local_0f0e0d0c-1111-4222-8333-444455556666")
    }

    @Test(arguments: [
        "local_../x", "session_01ABC", "local_", "local_" + String(repeating: "a", count: 65), "", "local_a b",
        "local_ä", "LOCAL_abc", "local_abc?x=1",
    ])
    func idsClaudeWouldRejectGiveNoLink(_ id: String) {
        #expect(SessionLinks.claudeDesktop(sessionID: id) == nil)
    }

    @Test func sixtyFourCharactersAreAllowed() {
        #expect(SessionLinks.isClaudeDesktopID("local_" + String(repeating: "a", count: 64)))
        #expect(SessionLinks.claudeDesktop(sessionID: nil) == nil)
    }

    @Test func aCodexThreadLinkIsLowercase() {
        let url = SessionLinks.codexThread(sessionID: "codex:0199A1B2-C3D4-7E5F-8A9B-0C1D2E3F4A5B")
        #expect(url?.absoluteString == "codex://threads/0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b")
    }

    @Test func codexIdsThatAreNotUUIDsGiveNoLink() {
        #expect(SessionLinks.codexThread(sessionID: "codex:not-a-uuid") == nil)
        #expect(SessionLinks.codexThread(sessionID: "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b") == nil)
        #expect(SessionLinks.codexThread(sessionID: "copilot:0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b") == nil)
    }

    // MARK: Desktop rows

    @Test func aClaudeDesktopRowOpensItsOwnSession() throws {
        let target = resolver(FakeTable(entries: [])).target(
            for: session("a", origin: .desktop, desktopSessionID: "local_abc-123"), sampleData: false
        )
        let url = try #require(SessionLinks.claudeDesktop(sessionID: "local_abc-123"))
        #expect(target == .link(url, appName: "Claude", fallback: Self.claude))
        #expect(target?.title == "Open in Claude")
    }

    /// No id (or one Claude wouldn't accept): Claude itself comes forward, still "Open in Claude".
    @Test func aClaudeDesktopRowWithoutAnIdBringsClaudeForward() {
        let resolver = resolver(FakeTable(entries: []))
        for id in [nil, "local_../x"] {
            let target = resolver.target(for: session("a", origin: .desktop, desktopSessionID: id), sampleData: false)
            #expect(target == .app(Self.claude, opensSession: true))
            #expect(target?.title == "Open in Claude")
        }
    }

    @Test func aClaudeDesktopRowWithoutClaudeRunningIsNotAButton() {
        let target = resolver(FakeTable(entries: []), apps: [Self.terminal]).target(
            for: session("a", origin: .desktop), sampleData: false
        )
        #expect(target == nil)
    }

    @Test func aCodexAppRowOpensItsThreadInTheHandlerApp() throws {
        let id = "codex:0199A1B2-C3D4-7E5F-8A9B-0C1D2E3F4A5B"
        let target = resolver(FakeTable(entries: [])).target(for: session(id, tool: .codex, origin: .desktop), sampleData: false)
        let url = try #require(SessionLinks.codexThread(sessionID: id))
        #expect(target == .link(url, appName: "ChatGPT", fallback: Self.codexApp))
        #expect(target?.title == "Open in ChatGPT")
    }

    // MARK: Terminal rows

    /// claude → zsh → login → Terminal.
    @Test func aTerminalRowShowsItsTerminal() {
        let table = FakeTable(entries: [
            ProcessEntry(pid: 900, parent: 890, command: "claude"),
            ProcessEntry(pid: 890, parent: 880, command: "zsh"),
            ProcessEntry(pid: 880, parent: 400, command: "login"),
            ProcessEntry(pid: 400, parent: 1, command: "Terminal"),
        ])
        let target = resolver(table).target(for: session("a", origin: .terminal, pid: 900), sampleData: false)
        #expect(target == .app(Self.terminal, opensSession: false))
        #expect(target?.title == "Show in Terminal")
    }

    /// The Claude app's terminal panel: its helper isn't a Dock app, so the walk goes on to Claude.
    @Test func helpersAreSkippedOnTheWayUp() {
        let table = FakeTable(entries: [
            ProcessEntry(pid: 900, parent: 890, command: "claude"),
            ProcessEntry(pid: 890, parent: 510, command: "zsh"),
            ProcessEntry(pid: 510, parent: 500, command: "Claude Helper"),
            ProcessEntry(pid: 500, parent: 1, command: "Claude"),
        ])
        let target = resolver(table).target(for: session("a", origin: .terminal, pid: 900), sampleData: false)
        #expect(target?.title == "Show in Claude")
    }

    @Test func anAgentAppIsNotAHost() {
        let table = FakeTable(entries: [
            ProcessEntry(pid: 900, parent: 700, command: "claude"),
            ProcessEntry(pid: 700, parent: 1, command: "Agent"),
        ])
        #expect(resolver(table).target(for: session("a", origin: .terminal, pid: 900), sampleData: false) == nil)
    }

    /// iTerm2's shells run under `iTermServer-<version>`, which launchd adopts.
    @Test func iTermServerStandsForITerm() {
        let table = FakeTable(entries: [
            ProcessEntry(pid: 900, parent: 890, command: "claude"),
            ProcessEntry(pid: 890, parent: 880, command: "zsh"),
            ProcessEntry(pid: 880, parent: 1, command: "iTermServer-3.6"),
        ])
        let target = resolver(table).target(for: session("a", tool: .copilot, origin: .terminal, pid: 900), sampleData: false)
        #expect(target?.title == "Show in iTerm")
    }

    /// tmux and ssh sessions end at launchd without an app: the row isn't a button.
    @Test func noAppAboveThePidGivesNoTarget() {
        let table = FakeTable(entries: [
            ProcessEntry(pid: 900, parent: 890, command: "claude"),
            ProcessEntry(pid: 890, parent: 1, command: "tmux"),
        ])
        #expect(resolver(table).target(for: session("a", origin: .terminal, pid: 900), sampleData: false) == nil)
        #expect(resolver(table).target(for: session("b", origin: .terminal, pid: 999), sampleData: false) == nil)
        #expect(resolver(table).target(for: session("c", origin: .terminal), sampleData: false) == nil)
    }

    // MARK: Codex CLI rows (no pid)

    private func codexCLI(_ path: String = "/Users/example/code/website") -> SessionInfo {
        session("codex:0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b", tool: .codex, origin: .terminal, projectPath: path)
    }

    @Test func aCodexCLIRowFindsItsProcessByFolder() {
        let table = FakeTable(
            entries: [
                ProcessEntry(pid: 900, parent: 890, command: "codex"),
                ProcessEntry(pid: 890, parent: 400, command: "zsh"),
                ProcessEntry(pid: 400, parent: 1, command: "Terminal"),
                ProcessEntry(pid: 950, parent: 410, command: "codex"),
            ],
            directories: [900: "/Users/example/code/website", 950: "/Users/example/code/other"]
        )
        let target = resolver(table).target(for: codexCLI("/Users/example/code/website/"), sampleData: false)
        #expect(target == .app(Self.terminal, opensSession: false))
    }

    /// Two terminals in the same folder can't be told apart.
    @Test func twoHostAppsInTheSameFolderGiveNoTarget() {
        let table = FakeTable(
            entries: [
                ProcessEntry(pid: 900, parent: 400, command: "codex"),
                ProcessEntry(pid: 400, parent: 1, command: "Terminal"),
                ProcessEntry(pid: 950, parent: 880, command: "codex"),
                ProcessEntry(pid: 880, parent: 1, command: "iTermServer-3.6"),
            ],
            directories: [900: "/Users/example/code/website", 950: "/Users/example/code/website"]
        )
        #expect(resolver(table).target(for: codexCLI(), sampleData: false) == nil)
    }

    /// The Codex app runs a `codex` of its own in the thread's folder: that one is the app's, not a terminal's.
    @Test func theCodexAppsOwnProcessIsLeftOut() {
        let table = FakeTable(
            entries: [
                ProcessEntry(pid: 900, parent: 400, command: "codex"),
                ProcessEntry(pid: 400, parent: 1, command: "Terminal"),
                ProcessEntry(pid: 960, parent: 600, command: "codex"),
                ProcessEntry(pid: 600, parent: 1, command: "ChatGPT"),
            ],
            directories: [900: "/Users/example/code/website", 960: "/Users/example/code/website"]
        )
        #expect(resolver(table).target(for: codexCLI(), sampleData: false) == .app(Self.terminal, opensSession: false))
    }

    @Test func anUnlistableProcessTableGivesNoTarget() {
        let table = FakeTable(entries: [ProcessEntry(pid: 900, parent: 400, command: "codex")], listable: false)
        #expect(resolver(table).target(for: codexCLI(), sampleData: false) == nil)
    }

    // MARK: Many rows at once (the panel opening)

    /// Counts the whole-list reads of a table.
    private struct CountingTable: ProcessTableReading {
        var table: FakeTable
        let listings = OSAllocatedUnfairLock(initialState: 0)

        func entry(pid: Int32) -> ProcessEntry? { table.entry(pid: pid) }
        func all() -> [ProcessEntry]? {
            listings.withLock { $0 += 1 }
            return table.all()
        }
        func workingDirectory(pid: Int32) -> String? { table.workingDirectory(pid: pid) }
    }

    /// The panel resolves every row as it opens, on the main thread: the process list is read once for all the Codex
    /// CLI rows, and each link scheme's handler app is looked up once.
    @Test func manyRowsShareOneProcessListAndOneHandlerLookupPerScheme() {
        let table = CountingTable(table: FakeTable(
            entries: [
                ProcessEntry(pid: 900, parent: 400, command: "codex"),
                ProcessEntry(pid: 400, parent: 1, command: "Terminal"),
                ProcessEntry(pid: 950, parent: 880, command: "codex"),
                ProcessEntry(pid: 880, parent: 1, command: "iTermServer-3.6"),
            ],
            directories: [900: "/Users/example/code/website", 950: "/Users/example/code/atlas"]
        ))
        let handlerLookups = OSAllocatedUnfairLock(initialState: [String]())
        let resolver = SessionTargetResolver(
            processes: table,
            appForPID: { pid in Self.apps.first { $0.pid == pid } },
            runningApp: { id in Self.apps.first { $0.bundleIdentifier == id } },
            handlerName: { url in
                handlerLookups.withLock { $0.append(url.scheme ?? "") }
                return ["claude": "Claude", "codex": "ChatGPT"][url.scheme ?? ""]
            }
        )
        func codex(_ last: String, _ origin: SessionOrigin, _ path: String? = nil) -> SessionInfo {
            session("codex:0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5\(last)", tool: .codex, origin: origin, projectPath: path)
        }
        let rows = [
            codex("b", .terminal, "/Users/example/code/website"),
            codex("c", .terminal, "/Users/example/code/atlas"),
            codex("d", .desktop),
            codex("e", .desktop),
            session("d1", origin: .desktop, desktopSessionID: "local_0f0e0d0c-1111-4222-8333-444455556666"),
            session("d2", origin: .desktop, desktopSessionID: "local_0f0e0d0c-1111-4222-8333-444455556667"),
        ]
        let targets = resolver.targets(for: rows, sampleData: false)
        #expect(targets[rows[0].id] == .app(Self.terminal, opensSession: false))
        #expect(targets[rows[1].id] == .app(Self.iTerm, opensSession: false))
        #expect(targets[rows[2].id]?.title == "Open in ChatGPT")
        #expect(targets[rows[5].id]?.title == "Open in Claude")
        #expect(table.listings.withLock { $0 } == 1)
        #expect(handlerLookups.withLock { $0 }.sorted() == ["claude", "codex"])
        // One row at a time gives the same targets.
        for row in rows {
            #expect(resolver.target(for: row, sampleData: false) == targets[row.id])
        }
    }

    // MARK: Sample data and names

    @Test func sampleDataIsNeverOpened() {
        let table = FakeTable(entries: [ProcessEntry(pid: 900, parent: 400, command: "claude")])
        let resolver = resolver(table)
        #expect(resolver.target(for: session("a", origin: .desktop, desktopSessionID: "local_abc"), sampleData: true) == nil)
        #expect(resolver.target(for: session("b", origin: .terminal, pid: 900), sampleData: true) == nil)
    }

    @Test func hostAppsGoByTheirShortNames() {
        #expect(HostAppNames.name(bundleIdentifier: "com.microsoft.VSCode", localizedName: "Code") == "VS Code")
        #expect(HostAppNames.name(bundleIdentifier: "com.todesktop.230313mzl4w4u92", localizedName: "Cursor") == "Cursor")
        #expect(HostAppNames.name(bundleIdentifier: HostAppNames.iTermBundleIdentifier, localizedName: "iTerm2") == "iTerm")
        #expect(HostAppNames.name(bundleIdentifier: "com.example.term", localizedName: "Kitty") == "Kitty")
        #expect(HostAppNames.name(bundleIdentifier: nil, localizedName: nil) == "the app")
    }
}

/// Opening a target: Launch Services first, `activate()` as the fallback (1.1 §14.3).
@MainActor
@Suite struct SessionOpeningTests {
    /// Records what was asked, and answers as set.
    private final class RecordingWorkspace: SessionWorkspace {
        var opensURLs = true
        var opensApps = true
        private(set) var calls: [String] = []

        func open(_ url: URL) async -> Bool {
            calls.append("open \(url.absoluteString)")
            return opensURLs
        }

        func openApplication(at bundleURL: URL) async -> Bool {
            calls.append("openApplication \(bundleURL.path)")
            return opensApps
        }

        func activate(pid: Int32) -> Bool {
            calls.append("activate \(pid)")
            return true
        }
    }

    private let claude = HostApp(
        pid: 500, bundleIdentifier: ClaudeDesktopApp.bundleIdentifier, name: "Claude",
        bundleURL: URL(fileURLWithPath: "/Applications/Claude.app"), isRegular: true
    )
    private let link = URL(string: "claude://code/continue?session=local_abc")!

    @Test func aLinkIsOpenedByItsHandler() async {
        let workspace = RecordingWorkspace()
        await SessionOpening.open(.link(link, appName: "Claude", fallback: claude), in: workspace)
        #expect(workspace.calls == ["open claude://code/continue?session=local_abc"])
    }

    @Test func aLinkThatFailsBringsItsAppForward() async {
        let workspace = RecordingWorkspace()
        workspace.opensURLs = false
        await SessionOpening.open(.link(link, appName: "Claude", fallback: claude), in: workspace)
        #expect(workspace.calls == ["open claude://code/continue?session=local_abc", "openApplication /Applications/Claude.app"])
    }

    @Test func anAppIsOpenedThroughLaunchServices() async {
        let workspace = RecordingWorkspace()
        await SessionOpening.open(.app(claude, opensSession: false), in: workspace)
        #expect(workspace.calls == ["openApplication /Applications/Claude.app"])
    }

    @Test func activateIsTheFallback() async {
        let workspace = RecordingWorkspace()
        workspace.opensApps = false
        await SessionOpening.open(.app(claude, opensSession: false), in: workspace)
        #expect(workspace.calls == ["openApplication /Applications/Claude.app", "activate 500"])

        let noBundle = HostApp(pid: 42, bundleIdentifier: nil, name: "Tool", bundleURL: nil, isRegular: true)
        let other = RecordingWorkspace()
        await SessionOpening.open(.app(noBundle, opensSession: false), in: other)
        #expect(other.calls == ["activate 42"])
    }
}
