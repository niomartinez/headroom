import Foundation
import HeadroomModel
import Testing
@testable import HeadroomShare

@Suite struct WidgetSnapshotFileTests {
    private let now = Date(timeIntervalSince1970: 1_790_250_000)

    private func session(_ index: Int) -> SessionInfo {
        SessionInfo(
            id: "s\(index)", name: "session \(index)", projectPath: "/Users/me/code/app\(index)", origin: .terminal,
            activity: .idle, activitySince: now, startedAt: now, pid: Int32(1000 + index),
            transcriptPath: "/Users/me/.claude/projects/app/s\(index).jsonl", context: nil,
            desktopSessionID: "local_0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a\(index)"
        )
    }

    private var snapshot: HeadroomSnapshot {
        HeadroomSnapshot(
            plan: .empty, sessions: (0..<15).map(session), terminalBridgeConnected: true, issues: [],
            generatedAt: now, codex: ToolUsage(tool: .codex, status: .noActivity)
        )
    }

    @Test func scrubsPathsPidsAndHiddenNames() {
        let file = WidgetSnapshotFile.scrubbing(
            snapshot, writtenAt: now, isSample: false, pillTool: .claude, showsSessionNames: false
        )
        #expect(file.version == WidgetSnapshotFile.currentVersion)
        #expect(file.snapshot.sessions.map(\.id) == (0..<12).map { "s\($0)" })
        #expect(file.snapshot.sessions.allSatisfy {
            $0.pid == nil && $0.projectPath == nil && $0.transcriptPath == nil && $0.desktopSessionID == nil
                && $0.name.isEmpty
        })
        let named = WidgetSnapshotFile.scrubbing(
            snapshot, writtenAt: now, isSample: false, pillTool: nil, showsSessionNames: true
        )
        #expect(named.snapshot.sessions[0].name == "session 0")
    }

    /// No widget shows the GitHub login, so it stays out of the shared file; the usage itself stays.
    @Test func leavesOutTheGitHubLogin() throws {
        var snapshot = snapshot
        snapshot.copilot = ToolUsage(
            tool: .copilot,
            limits: [ToolLimit(
                window: .monthly, usedPercent: 34, used: 512, allowance: 1_500, unit: .aiCredits, resetsAt: nil,
                observedAt: now
            )],
            status: .ok, planName: "Pro", account: "octocat"
        )
        let file = WidgetSnapshotFile.scrubbing(
            snapshot, writtenAt: now, isSample: false, pillTool: nil, showsSessionNames: true
        )
        #expect(file.snapshot.copilot?.account == nil)
        #expect(file.snapshot.copilot?.limits == snapshot.copilot?.limits)
        #expect(file.snapshot.copilot?.status == .ok)
        #expect(!String(decoding: try file.encoded(), as: UTF8.self).contains("octocat"))
    }

    @Test func codecRoundTrips() throws {
        let file = WidgetSnapshotFile.scrubbing(
            snapshot, writtenAt: now, isSample: true, pillTool: .codex, showsSessionNames: true
        )
        #expect(WidgetSnapshotFile.decoded(from: try file.encoded()) == file)
        let json = String(decoding: try file.encoded(), as: UTF8.self)
        #expect(json.contains(#""writtenAt":1790250000"#))
    }

    @Test func otherVersionsAreNotDecoded() throws {
        var file = WidgetSnapshotFile.scrubbing(
            snapshot, writtenAt: now, isSample: false, pillTool: nil, showsSessionNames: true
        )
        file.version = WidgetSnapshotFile.currentVersion + 1
        #expect(WidgetSnapshotFile.decoded(from: try file.encoded()) == nil)
        #expect(WidgetSnapshotFile.decoded(from: Data("{}".utf8)) == nil)
    }

    /// The app writes atomically; the widget reads back the same file, and nothing when it's missing, garbage or
    /// oversized.
    @Test func writesAtomicallyAndReadsBack() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent(WidgetShare.fileName)

        #expect(WidgetSnapshotFile.read(from: url) == nil)
        let file = WidgetSnapshotFile.scrubbing(
            snapshot, writtenAt: now, isSample: false, pillTool: .claude, showsSessionNames: true
        )
        try file.write(to: url)
        #expect(WidgetSnapshotFile.read(from: url) == file)
        // A rewrite replaces the file whole; no temporary file is left behind.
        var newer = file
        newer.writtenAt = now.addingTimeInterval(60)
        try newer.write(to: url)
        #expect(WidgetSnapshotFile.read(from: url) == newer)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [WidgetShare.fileName])

        try Data("not json".utf8).write(to: url)
        #expect(WidgetSnapshotFile.read(from: url) == nil)
        try Data(repeating: 0x20, count: WidgetSnapshotFile.maxFileSize + 1).write(to: url)
        #expect(WidgetSnapshotFile.read(from: url) == nil)
    }

    /// The file never carries what could identify a folder or a process, whatever the snapshot holds.
    @Test func encodedFileHasNoPathsOrPids() throws {
        let json = String(decoding: try WidgetSnapshotFile.scrubbing(
            snapshot, writtenAt: now, isSample: false, pillTool: .claude, showsSessionNames: true
        ).encoded(), as: UTF8.self)
        #expect(!json.contains("/Users/"))
        #expect(!json.contains("\"pid\""))
        #expect(!json.contains("transcriptPath"))
        #expect(!json.contains("projectPath"))
        // The Claude app's session id (1.1 §14.3) stays on the Mac too.
        #expect(!json.contains("desktopSessionID"))
        #expect(!json.contains("local_"))
    }

    @Test func groupNeedsInfoPlistAndSignedEntitlement() {
        // The test runner's Info.plist names no group, and an unsigned process has no entitlement.
        #expect(WidgetShare.groupIdentifier() == nil)
        #expect(WidgetShare.fileURL() == nil)
        #expect(WidgetShare.groupIdentifier(bundle: .main, signedGroups: ["L237BMXGB6.com.niomartinez.headroom"]) == nil)
    }

    /// A bundle in a fresh folder (`Bundle` caches by path) whose Info.plist sets `HeadroomAppGroup` to `group`.
    private func temporaryBundle(naming group: String) throws -> (bundle: Bundle, folder: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString).bundle")
        let contents = folder.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.example.share-tests", WidgetShare.appGroupInfoKey: group]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return (try #require(Bundle(url: folder)), folder)
    }

    /// A team-signed build: Info.plist names the group and the signature claims it.
    @Test func groupWhenInfoPlistAndSignatureAgree() throws {
        let group = "L237BMXGB6.com.niomartinez.headroom"
        let (bundle, folder) = try temporaryBundle(naming: group)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(WidgetShare.groupIdentifier(bundle: bundle, signedGroups: [group]) == group)
        #expect(WidgetShare.groupIdentifier(bundle: bundle, signedGroups: ["L237BMXGB6.com.example.other", group]) == group)
        // Debug and ad-hoc builds carry the Info.plist key but claim no group.
        #expect(WidgetShare.groupIdentifier(bundle: bundle, signedGroups: []) == nil)
        #expect(WidgetShare.groupIdentifier(bundle: bundle, signedGroups: ["L237BMXGB6.com.example.other"]) == nil)
    }

    /// An Info.plist whose build setting wasn't expanded never names a group, whatever the signature says.
    @Test func unexpandedTeamPrefixIsNoGroup() throws {
        let literal = "$(TeamIdentifierPrefix)com.niomartinez.headroom"
        let (bundle, folder) = try temporaryBundle(naming: literal)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(WidgetShare.groupIdentifier(bundle: bundle, signedGroups: [literal]) == nil)

        let (empty, emptyFolder) = try temporaryBundle(naming: "")
        defer { try? FileManager.default.removeItem(at: emptyFolder) }
        #expect(WidgetShare.groupIdentifier(bundle: empty, signedGroups: [""]) == nil)
    }

    @Test func permanentIdentifiers() {
        #expect(WidgetShare.limitsKind == "com.niomartinez.headroom.limits")
        #expect(WidgetShare.sessionsKind == "com.niomartinez.headroom.sessions")
        #expect(WidgetShare.openPanelURL.scheme == "com.niomartinez.headroom")
        #expect(WidgetShare.openPanelURL.host == "panel")
    }
}
