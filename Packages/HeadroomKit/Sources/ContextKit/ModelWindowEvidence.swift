import os

/// Model ids seen using more than the standard 200k-token window in a main-thread reply (spec §2.3),
/// remembered for as long as the owning reader lives: across polls and across transcripts. Matched
/// ignoring case. Thread-safe. When it would grow past `limit` ids it starts over, like `BoundedCache`.
final class ModelWindowEvidence: Sendable {
    private let models = OSAllocatedUnfairLock(initialState: Set<String>())
    private let limit: Int

    init(limit: Int = 256) {
        self.limit = limit
    }

    /// Remembers `usage.model` when the reply used more than the standard window.
    func record(_ usage: TranscriptUsage) {
        guard usage.usedTokens > ContextWindowResolver.standardWindow, let model = usage.model else { return }
        let key = model.lowercased()
        models.withLock { models in
            guard !models.contains(key) else { return }
            if models.count >= limit { models.removeAll() }
            models.insert(key)
        }
    }

    func contains(model: String?) -> Bool {
        guard let key = model?.lowercased() else { return false }
        return models.withLock { $0.contains(key) }
    }
}
