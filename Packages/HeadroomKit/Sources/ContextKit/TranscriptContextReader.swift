import Darwin
import Foundation

/// Tail-reads transcripts and caches the result by (path, size, mtime) (spec §2.3), so polling an
/// unchanged transcript costs one `stat`. Files with nothing usable are cached too. Thread-safe.
///
/// It also remembers, for its whole life, every model id it has seen above the standard 200k-token window
/// in a main-thread reply, and marks results from those models (`TranscriptUsage.modelExceededStandardWindow`),
/// cached ones included. Keep one reader across polls so that evidence builds up.
public final class TranscriptContextReader: Sendable {
    private struct CacheEntry: Sendable {
        var signature: FileSignature
        var usage: TranscriptUsage?
    }

    private let scanner: TranscriptTailScanner
    private let cache = BoundedCache<CacheEntry>()
    private let evidence = ModelWindowEvidence()
    private let reads = Counter()

    public init() {
        scanner = TranscriptTailScanner()
    }

    /// Custom window sizes, for tests.
    init(initialWindow: Int, maxWindow: Int) {
        scanner = TranscriptTailScanner(initialWindow: initialWindow, maxWindow: maxWindow)
    }

    /// The newest main-thread assistant entry with usage, or nil when the file is missing, is not a
    /// regular file, or has none within the last 8 MB.
    public func latestUsage(at url: URL) -> TranscriptUsage? {
        guard url.isFileURL else { return nil }
        let path = url.path
        guard let status = FileStatus.of(path: path), status.isRegularFile else {
            cache[path] = nil
            return nil
        }
        if let entry = cache[path], entry.signature == status.signature {
            return withEvidence(entry.usage)
        }
        let entry = read(path: path)
        cache[path] = entry
        return withEvidence(entry?.usage)
    }

    /// `usage` marked with what is known now about its model, which may be more than when it was read.
    private func withEvidence(_ usage: TranscriptUsage?) -> TranscriptUsage? {
        guard var usage else { return nil }
        usage.modelExceededStandardWindow = evidence.contains(model: usage.model)
        return usage
    }

    /// Number of times a transcript was actually read, i.e. cache misses (for tests).
    var readCount: Int { reads.value }

    private func read(path: String) -> CacheEntry? {
        // O_NONBLOCK: should the path have been swapped for a FIFO since it was examined, opening it
        // must not wait for a writer.
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        guard let status = FileStatus.of(descriptor: descriptor), status.isRegularFile else { return nil }
        reads.increment()
        // The older lines already read are searched only while the newest entry's window would be a guess:
        // a known window needs no evidence, and the search decodes every older reply in the window.
        let finding = scanner.newestUsage(descriptor: descriptor, size: status.signature.size) { [evidence] newest in
            ContextWindowResolver.window(
                model: newest.model,
                usedTokens: newest.usedTokens,
                modelExceededStandardWindow: evidence.contains(model: newest.model)
            ).basis == .assumed
        }
        if let finding {
            evidence.record(finding.usage)
            finding.olderAboveStandardWindow.forEach(evidence.record)
        }
        return CacheEntry(signature: status.signature, usage: finding?.usage)
    }
}
