import Foundation
import HeadroomModel
import Security

/// Where the app and the widget extension meet (1.1 §5.1, §5.3). The app is the only writer of the shared file;
/// the widget only decodes it and never reads user folders.
public enum WidgetShare {
    public static let fileName = "widget-snapshot.json"
    /// The Limits widget's kind. Permanent: renaming it orphans every placed widget.
    public static let limitsKind = "com.niomartinez.headroom.limits"
    /// The Sessions widget's kind. Permanent: renaming it orphans every placed widget.
    public static let sessionsKind = "com.niomartinez.headroom.sessions"
    /// Every widget's `widgetURL`: the app opens the panel under the pill.
    public static let openPanelURL: URL = {
        // Debug has its own registered URL scheme, so its widgets cannot reopen the installed app.
        let scheme = Bundle.main.object(forInfoDictionaryKey: "HeadroomURLScheme") as? String
        let isDevelopment = scheme == "com.niomartinez.headroom.dev"
        return URL(string: isDevelopment ? "com.niomartinez.headroom.dev://panel" : "com.niomartinez.headroom://panel")!
    }()
    /// The Info.plist key naming the App Group, `L237BMXGB6.com.niomartinez.headroom` in team-signed builds and empty
    /// otherwise (Config/Headroom-Variants.xcconfig). Permanent too.
    public static let appGroupInfoKey = "HeadroomAppGroup"

    private static let applicationGroupsEntitlement = "com.apple.security.application-groups"

    /// The App Group, only when `bundle`'s Info.plist names it **and** this process's signed entitlements contain
    /// it. Debug and ad-hoc builds claim no group, so they never touch or prompt for the container.
    public static func groupIdentifier(bundle: Bundle = .main) -> String? {
        groupIdentifier(bundle: bundle, signedGroups: signedApplicationGroups())
    }

    static func groupIdentifier(bundle: Bundle, signedGroups: [String]) -> String? {
        guard let group = bundle.object(forInfoDictionaryKey: appGroupInfoKey) as? String,
              !group.isEmpty, !group.contains("$("), signedGroups.contains(group)
        else { return nil }
        return group
    }

    /// The shared file in the App Group container, or nil without a group. `containerURL` returns a URL on macOS
    /// even when the container can't be used, so treat any I/O failure on it as "no data".
    public static func fileURL(bundle: Bundle = .main) -> URL? {
        guard let group = groupIdentifier(bundle: bundle) else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent(fileName)
    }

    /// The `application-groups` entitlement of the running process, from its code signature.
    private static func signedApplicationGroups() -> [String] {
        guard let task = SecTaskCreateFromSelf(nil) else { return [] }
        let value = SecTaskCopyValueForEntitlement(task, applicationGroupsEntitlement as CFString, nil)
        return value as? [String] ?? []
    }
}

/// The shared file's contents (1.1 §5.3), scrubbed of paths and pids, and of names when the user hides them.
public struct WidgetSnapshotFile: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    /// At most this many sessions are written, in display order.
    public static let maxSessions = 12

    /// A file older than this reads "Headroom isn't running" (1.1 §5.6): the app rewrites it at least every
    /// 15 minutes while it runs (§5.4).
    public static let notRunningAfter: TimeInterval = 35 * 60

    /// Unknown or newer → the widget shows "Open Headroom".
    public var version: Int
    /// The app's heartbeat: "Headroom isn't running" once it's over 35 minutes old.
    public var writtenAt: Date
    public var isSample: Bool
    /// The app's resolved "Rings show" tool: what the widgets' Automatic means.
    public var pillTool: ToolID?
    public var showsSessionNames: Bool
    public var snapshot: HeadroomSnapshot

    public init(
        version: Int = WidgetSnapshotFile.currentVersion,
        writtenAt: Date,
        isSample: Bool,
        pillTool: ToolID?,
        showsSessionNames: Bool,
        snapshot: HeadroomSnapshot
    ) {
        self.version = version
        self.writtenAt = writtenAt
        self.isSample = isSample
        self.pillTool = pillTool
        self.showsSessionNames = showsSessionNames
        self.snapshot = snapshot
    }

    /// A file for `snapshot`, scrubbed: sessions lose `pid`, `transcriptPath`, `projectPath` and `desktopSessionID`
    /// (1.1 §14.3), their names become `""` unless `showsSessionNames`, and only the first `maxSessions` are kept.
    /// Copilot's GitHub login is left out too: no widget shows it.
    public static func scrubbing(
        _ snapshot: HeadroomSnapshot, writtenAt: Date, isSample: Bool, pillTool: ToolID?, showsSessionNames: Bool
    ) -> WidgetSnapshotFile {
        var scrubbed = snapshot
        scrubbed.sessions = snapshot.sessions.prefix(maxSessions).map { session in
            var session = session
            session.pid = nil
            session.transcriptPath = nil
            session.projectPath = nil
            session.desktopSessionID = nil
            if !showsSessionNames { session.name = "" }
            return session
        }
        scrubbed.copilot?.account = nil
        return WidgetSnapshotFile(
            writtenAt: writtenAt, isSample: isSample, pillTool: pillTool, showsSessionNames: showsSessionNames,
            snapshot: scrubbed
        )
    }

    /// JSON with dates in epoch seconds.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// The file in `data`, or nil when it isn't one of `currentVersion` (unreadable, unknown or newer).
    public static func decoded(from data: Data) -> WidgetSnapshotFile? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let header = try? decoder.decode(VersionHeader.self, from: data),
              header.version == currentVersion
        else { return nil }
        return try? decoder.decode(WidgetSnapshotFile.self, from: data)
    }

    /// The file at `url`, or nil when it is missing, unreadable, larger than `maxFileSize` or not of
    /// `currentVersion`: the widget then shows "Open Headroom". Nothing else is ever read.
    public static func read(from url: URL) -> WidgetSnapshotFile? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxFileSize + 1), data.count <= maxFileSize else { return nil }
        return decoded(from: data)
    }

    /// Writes the file atomically (a temporary file next to `url`, then a rename), so the widget never reads half a
    /// file.
    public func write(to url: URL) throws {
        try encoded().write(to: url, options: .atomic)
    }

    /// 12 sessions and three tools take a few kilobytes; anything far bigger isn't a file Headroom wrote.
    static let maxFileSize = 1 << 20

    /// True while the file is at most `notRunningAfter` old: the app is still writing it.
    public func isHeadroomRunning(at now: Date) -> Bool {
        now.timeIntervalSince(writtenAt) <= Self.notRunningAfter
    }

    private struct VersionHeader: Decodable {
        var version: Int
    }
}
