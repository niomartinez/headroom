import ContextKit
import Foundation

/// Thread titles from `session_index.jsonl` (1.1 §3.2): append-only, the newest line per id wins. Tail-read newest
/// first; when the file only grew, just the appended lines are read.
struct SessionIndexCache {
    private static let needle = Array(#""thread_name""#.utf8)

    private var signature: FileSignature?
    private var resumeOffset: Int64 = 0
    /// Thread id → the newest `thread_name` (possibly empty) within the tail read so far.
    private(set) var names: [String: String] = [:]

    /// Re-reads when the file changed; stats it every call.
    mutating func refresh(_ url: URL, files: CodexFileAccess, reader: JSONLTailReader) {
        guard let current = files.signature(of: url), current.isRegularFile else {
            signature = nil
            names = [:]
            return
        }
        guard current != signature else { return }
        let appendOnly = signature.map { current.isAppend(to: $0) } ?? false
        let start = appendOnly ? resumeOffset : 0
        var found: [String: String] = [:]
        let result: (JSONLTailReader.Scan, FileSignature)? = files.withOpenFile(url) { descriptor, opened in
            let decoder = JSONDecoder()
            let scan = reader.scan(descriptor: descriptor, from: start, size: opened.size) { line in
                guard line.contains(Self.needle),
                      let record = try? decoder.decode(SessionIndexRecord.self, from: line.data),
                      let id = record.id, found[id] == nil
                else { return .next }
                found[id] = record.threadName ?? ""
                return .next
            }
            return (scan, opened)
        }
        guard let (scan, opened) = result else {
            signature = nil
            names = [:]
            return
        }
        if appendOnly {
            names.merge(found) { _, newer in newer }
        } else {
            names = found
        }
        signature = opened
        resumeOffset = scan.resumeOffset
    }

    /// The thread's title, trimmed; nil when none or empty.
    func title(threadID: String) -> String? {
        guard let name = names[threadID]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        return name
    }
}

/// Threads Codex imported from other agents (`external_agent_session_imports.json`, 1.1 §3.5): read whole when it
/// changes, at most 4 MB, else ignored.
struct ImportsCache {
    static let maxBytes: Int64 = 4 * 1_024 * 1_024

    private var signature: FileSignature?
    /// Imported thread id → when it was imported.
    private(set) var imports: [String: Date] = [:]

    mutating func refresh(_ url: URL, files: CodexFileAccess) {
        guard let current = files.signature(of: url), current.isRegularFile, current.size <= Self.maxBytes else {
            signature = nil
            imports = [:]
            return
        }
        guard current != signature else { return }
        signature = current
        let data: [UInt8]? = files.withOpenFile(url) { descriptor, opened in
            guard opened.size <= Self.maxBytes else { return nil }
            return CodexFileAccess.readPrefix(descriptor, count: Int(opened.size))
        }
        imports = data.flatMap { try? JSONDecoder().decode(ImportsFile.self, from: Data($0)) }?.imports ?? [:]
    }
}
