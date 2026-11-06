import Foundation
import HeadroomModel

/// What the Claude and Codex apps record about which sessions the user has looked at (1.1.2, spec 1.1 §14.15): a
/// just-finished session the user opened in its own app leaves Just finished, as a wait answered there leaves Needs
/// you.
public struct SessionViewSignals: Sendable, Equatable {
    /// Claude app session (`SessionInfo.desktopSessionID`, `local_…`) → when the user last opened it in the Claude
    /// app (`lastFocusedAt`). Only for the listed Claude app sessions whose file was readable.
    public var claudeFocusedAt: [String: Date]
    /// Codex thread ids (without `codex:`) the Codex app shows as unread; nil when its state couldn't be read.
    public var codexUnread: Set<String>?

    public init(claudeFocusedAt: [String: Date] = [:], codexUnread: Set<String>? = nil) {
        self.claudeFocusedAt = claudeFocusedAt
        self.codexUnread = codexUnread
    }

    /// The Claude app session opened most recently: the one on screen while the Claude app is in front.
    public var claudeMostRecentlyFocused: String? {
        claudeFocusedAt.max { $0.value < $1.value }?.key
    }
}

/// Reads `SessionViewSignals`, cheaply enough for the 2 s poll: the first 4 KB of each Claude app session file
/// (`lastFocusedAt` is in its first kilobyte; the files are about 1 MB) and, only when it changed, the Codex app's
/// global state for its unread thread list. Nothing else in either file is kept. Not thread-safe: `SnapshotWorker`
/// owns it.
public final class SessionViewReader {
    static let headLength = 4096
    /// The Codex app's state file is about 2.5 MB; anything far larger is not the format we know.
    static let codexStateLimit = 32 * 1024 * 1024

    private let claudeSessionsDirectory: URL
    private let codexStateFile: URL?
    /// `local_…` → its file under `claude-code-sessions/<account>/<org>/`.
    private var claudeFiles: [String: URL] = [:]
    private var codexCache: (stamp: FileStamp, unread: Set<String>?)?

    public init(paths: ClaudePaths, codex: CodexPaths?) {
        claudeSessionsDirectory = paths.desktopSupportDirectory
            .appendingPathComponent("claude-code-sessions", isDirectory: true)
        codexStateFile = codex?.globalStateFile
    }

    /// `claudeDesktopIDs`: the listed Claude app sessions to read; `codex`: whether to read Codex's unread threads.
    public func read(claudeDesktopIDs: Set<String>, codex: Bool) -> SessionViewSignals {
        var signals = SessionViewSignals()
        if !claudeDesktopIDs.isEmpty {
            if claudeDesktopIDs.contains(where: { claudeFiles[$0] == nil }) {
                indexClaudeFiles()
            }
            for id in claudeDesktopIDs {
                if let url = claudeFiles[id], let focused = Self.lastFocusedAt(in: url) {
                    signals.claudeFocusedAt[id] = focused
                }
            }
        }
        if codex {
            signals.codexUnread = codexUnread()
        }
        return signals
    }

    // MARK: Claude

    /// Two levels of folders, a handful of entries each; only `local_*.json` names are kept.
    private func indexClaudeFiles() {
        let manager = FileManager.default
        var found: [String: URL] = [:]
        for account in (try? manager.contentsOfDirectory(at: claudeSessionsDirectory, includingPropertiesForKeys: nil)) ?? [] {
            for organization in (try? manager.contentsOfDirectory(at: account, includingPropertiesForKeys: nil)) ?? [] {
                for file in (try? manager.contentsOfDirectory(at: organization, includingPropertiesForKeys: nil)) ?? []
                where file.pathExtension == "json" && file.lastPathComponent.hasPrefix("local_") {
                    found[file.deletingPathExtension().lastPathComponent] = file
                }
            }
        }
        claudeFiles = found
    }

    /// `"lastFocusedAt":<epoch ms>` within the file's first 4 KB; nil when missing or implausible.
    static func lastFocusedAt(in url: URL) -> Date? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: headLength) else { return nil }
        return lastFocusedAt(head: head)
    }

    static func lastFocusedAt(head: Data) -> Date? {
        let text = String(decoding: head, as: UTF8.self)
        guard let match = text.firstMatch(of: #/"lastFocusedAt"\s*:\s*(\d{12,14})/#),
              let milliseconds = Double(match.1)
        else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    // MARK: Codex

    private struct FileStamp: Equatable {
        var size: Int
        var modified: Date
    }

    /// Read again only when the file's size or modification time changed.
    private func codexUnread() -> Set<String>? {
        guard let url = codexStateFile,
              let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
              values.isRegularFile == true, let size = values.fileSize, let modified = values.contentModificationDate,
              size <= Self.codexStateLimit
        else {
            codexCache = nil
            return nil
        }
        let stamp = FileStamp(size: size, modified: modified)
        if let codexCache, codexCache.stamp == stamp { return codexCache.unread }
        let unread = (try? Data(contentsOf: url)).flatMap(Self.codexUnread(in:))
        codexCache = (stamp, unread)
        return unread
    }

    /// `electron-thread-read-state-v1.unreadByIdentity`: identity → host → unread thread ids, all joined. Nil when
    /// the file isn't the format we know.
    static func codexUnread(in data: Data) -> Set<String>? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = root["electron-thread-read-state-v1"] as? [String: Any],
              let byIdentity = state["unreadByIdentity"] as? [String: Any]
        else { return nil }
        var unread = Set<String>()
        for case let byHost as [String: Any] in byIdentity.values {
            for case let ids as [Any] in byHost.values {
                for case let id as String in ids {
                    unread.insert(id.lowercased())
                }
            }
        }
        return unread
    }
}
