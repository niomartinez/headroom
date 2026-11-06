import ContextKit
import Foundation
import HeadroomModel
import SessionKit

/// Fills in `SessionInfo.context` (spec §2.3). Long-lived: the locator remembers where each transcript is and
/// the reader caches each transcript's result by (path, size, mtime), so an unchanged session costs two `stat`s.
struct SessionContextFiller {
    let locator: TranscriptLocator
    let reader = TranscriptContextReader()

    init(projectsDirectory: URL) {
        locator = TranscriptLocator(projectsDirectory: projectsDirectory)
    }

    /// `bridge` is every bridge record read, visible or not: all of them teach window sizes.
    func filling(_ sessions: [SessionInfo], bridge: [BridgeSessionRecord]) -> [SessionInfo] {
        let windows = WindowSizes(bridge: bridge)
        return sessions.map { session in
            var session = session
            guard let url = locator.transcriptURL(forSession: session.id, hint: session.transcriptPath) else {
                return session
            }
            session.transcriptPath = url.path
            if let usage = reader.latestUsage(at: url) {
                session.context = ContextWindowResolver.contextUsage(
                    for: usage,
                    exactFromStatusLine: windows.exact[session.id],
                    learned: windows.learned(for: usage)
                )
            }
            return session
        }
    }
}

/// Context window sizes reported by status lines (spec §2.4): exact per session, and learned per model.
struct WindowSizes {
    /// `context_window_size` from a session's own status line, by session id.
    let exact: [String: Int]
    /// `context_window_size` by model key (see `modelKey`), from every status line that reports both.
    let byModel: [String: Int]

    init(bridge: [BridgeSessionRecord]) {
        exact = Dictionary(
            bridge.compactMap { record in record.contextWindowSize.flatMap { $0 > 0 ? (record.sessionId, $0) : nil } },
            uniquingKeysWith: max
        )
        // Two status lines can disagree for one key (a `[1m]` and a standard variant of the same model):
        // the larger size wins, as a window too small shows a context bar that is simply wrong.
        byModel = Dictionary(
            bridge.compactMap { record in
                guard let model = record.modelId, let size = record.contextWindowSize, size > 0 else { return nil }
                return (Self.modelKey(model), size)
            },
            uniquingKeysWith: max
        )
    }

    /// The model id without a `[1m]` suffix: status lines report `claude-opus-5-5[1m]` where transcripts say
    /// `claude-opus-5-5`.
    static func modelKey(_ model: String) -> String {
        model.lowercased().hasSuffix("[1m]") ? String(model.dropLast(4)) : model
    }

    /// The learned size for the transcript's model, keyed by its raw id as `ContextWindowResolver` looks it up.
    /// A size smaller than the tokens already in use is certainly not this session's window and is left out, so
    /// the resolver's other rules decide.
    func learned(for usage: TranscriptUsage) -> [String: Int] {
        guard let model = usage.model, let size = byModel[Self.modelKey(model)], size >= usage.usedTokens else {
            return [:]
        }
        return [model: size]
    }
}
