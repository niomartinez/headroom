import CodexKit
import Foundation
import HeadroomModel
import SessionKit

/// The reader for one tool's granted folder (1.1 §3.1, §4.9), made again only when the folder changes, so the
/// reader's own caches survive from one poll to the next. Released when the tool isn't tracked any more.
struct GrantedFolderReader<Reader> {
    private let make: (URL) -> Reader
    private var current: (path: String, reader: Reader)?
    /// Number of readers made (for tests).
    private(set) var made = 0

    init(make: @escaping (URL) -> Reader) {
        self.make = make
    }

    /// The reader for `folder`: the current one while the folder is the same (compared by standardized path, so a
    /// trailing slash doesn't count as a change), else a new one.
    mutating func reader(for folder: URL) -> Reader {
        let path = folder.standardizedFileURL.path
        if let current, current.path == path {
            return current.reader
        }
        let fresh = make(folder)
        made += 1
        current = (path, fresh)
        return fresh
    }

    /// Drops the current reader and its caches.
    mutating func release() {
        current = nil
    }
}

/// What `SnapshotBuilder` reads Copilot CLI sessions through (1.1 §4.9): SessionKit's `CopilotSessionReader`, or a
/// fake in tests.
protocol CopilotSessionReading {
    func readSessions(now: Date) -> [SessionInfo]
}

#if HEADROOM_COPILOT_CLI
extension CopilotSessionReader: CopilotSessionReading {}
#else
/// A build without Copilot CLI support (gate G2) never asks for a reader, since `SourceSelection.readsCopilotCLI` is
/// always false there. This one only gives the builder something to hold.
private struct NoCopilotCLISessions: CopilotSessionReading {
    func readSessions(now: Date) -> [SessionInfo] { [] }
}
#endif

extension SnapshotBuilder {
    /// The real Codex reader for a granted folder: CodexKit's `CodexReader`, with `runtime` deciding liveness.
    static func codexReaders(runtime: any CodexRuntimeProbing) -> (URL) -> any CodexReadingProviding {
        return { CodexReader(codexHome: $0, runtime: runtime) }
    }

    /// The real Copilot CLI reader for a granted folder: SessionKit's `CopilotSessionReader`, with `probe` deciding
    /// liveness as it does for Claude's sessions.
    static func copilotCLIReaders(probe: any ProcessProbing) -> (URL) -> any CopilotSessionReading {
        #if HEADROOM_COPILOT_CLI
        return { CopilotSessionReader(copilotHome: $0, probe: probe) }
        #else
        return { _ in NoCopilotCLISessions() }
        #endif
    }
}
