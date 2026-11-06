import Foundation

/// Reads the terminal bridge's per-session files, `~/.claude/headroom/sessions` (spec §2.4, §2.5).
public struct BridgeSessionReader: Sendable {
    /// `~/.claude/headroom/sessions`
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// One record per session id found in the directory; missing directory → `[]`.
    ///
    /// The id comes from the file's own `session_id` when present, else from its name, so a
    /// temporary file left mid-write never shows up as a separate session. When several files of
    /// one kind name the same id, the newest `ts` wins.
    public func readRecords() -> [BridgeSessionRecord] {
        // `contentsOfDirectory(at:)` refuses a directory that is itself a symlink.
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory.resolvingSymlinksInPath(),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var hooks: [String: HookFile] = [:]
        var statusLines: [String: StatusLineFile] = [:]
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = file.lastPathComponent
            if let stem = name.stem(removing: HookFile.suffix), let json = JSONObject(contentsOf: file) {
                hooks.keepNewest(HookFile(json: json), fallbackId: stem)
            } else if let stem = name.stem(removing: StatusLineFile.suffix), let json = JSONObject(contentsOf: file) {
                statusLines.keepNewest(StatusLineFile(json: json), fallbackId: stem)
            }
        }

        return Set(hooks.keys).union(statusLines.keys).sorted().map { id in
            BridgeSessionRecord(sessionId: id, hook: hooks[id], statusLine: statusLines[id])
        }
    }
}

private extension Dictionary where Key == String, Value: BridgeFile {
    mutating func keepNewest(_ file: Value, fallbackId: String) {
        let id = file.header.sessionId ?? fallbackId
        if let existing = self[id], !file.header.isNewer(than: existing.header) { return }
        self[id] = file
    }
}

private extension String {
    /// The non-empty part before `suffix`, or nil when the name does not end with it.
    func stem(removing suffix: String) -> String? {
        guard hasSuffix(suffix), count > suffix.count else { return nil }
        return String(dropLast(suffix.count))
    }
}
