import Foundation

/// Finds a session's transcript under `~/.claude/projects` (spec §2.3).
///
/// Found locations are cached per session id (shared by copies of the locator) and re-verified on
/// every call, so a transcript that moves or disappears is searched for again. A search that finds
/// nothing is remembered for `missRetryInterval`, so a session without a transcript (yet) does not
/// scan every project directory on each 2 s poll, while a transcript that appears later is still
/// found within that interval.
public struct TranscriptLocator: Sendable {
    /// How long a search that found nothing is trusted before searching again.
    public static let missRetryInterval: TimeInterval = 10

    public let projectsDirectory: URL
    private let cache = BoundedCache<URL>()
    /// Session id → `uptime()` of the search that found nothing.
    private let misses = BoundedCache<TimeInterval>()
    private let searches = Counter()
    private let uptime: @Sendable () -> TimeInterval

    public init(projectsDirectory: URL) {
        self.init(projectsDirectory: projectsDirectory, uptime: Self.monotonicSeconds)
    }

    /// `uptime` is a monotonic clock in seconds (injectable for tests).
    init(projectsDirectory: URL, uptime: @escaping @Sendable () -> TimeInterval) {
        self.projectsDirectory = projectsDirectory
        self.uptime = uptime
    }

    /// `hint` is a transcript path reported by the bridge; used when it exists.
    /// Otherwise searches `projects/*/<sessionID>.jsonl`.
    public func transcriptURL(forSession sessionID: String, hint: String?) -> URL? {
        if let hint, let url = Self.usableHint(hint) {
            return url
        }
        guard Self.isPlausibleSessionID(sessionID) else { return nil }
        if let cached = cache[sessionID], FileStatus.of(path: cached.path)?.isRegularFile == true {
            return cached
        }
        let now = uptime()
        if let missedAt = misses[sessionID] {
            // A clock that went backwards (it shouldn't) never pins a miss.
            let elapsed = now - missedAt
            if elapsed >= 0, elapsed < Self.missRetryInterval { return nil }
        }
        let found = search(fileName: "\(sessionID).jsonl")
        cache[sessionID] = found
        misses[sessionID] = found == nil ? now : nil
        return found
    }

    /// Seconds on a clock that never jumps and keeps counting during sleep.
    @Sendable private static func monotonicSeconds() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

    /// Number of directory searches so far (for tests).
    var searchCount: Int { searches.value }

    /// The newest `projects/*/<fileName>` that is a regular file. Directory names may start with "-".
    private func search(fileName: String) -> URL? {
        searches.increment()
        let root = projectsDirectory.path
        guard let projects = try? FileManager.default.contentsOfDirectory(atPath: root) else { return nil }
        var best: (path: String, signature: FileSignature)?
        for project in projects {
            let path = (root as NSString).appendingPathComponent(project)
            let candidate = (path as NSString).appendingPathComponent(fileName)
            guard let status = FileStatus.of(path: candidate), status.isRegularFile else { continue }
            if let current = best, !status.signature.isModified(after: current.signature) { continue }
            best = (candidate, status.signature)
        }
        return best.map { URL(fileURLWithPath: $0.path, isDirectory: false) }
    }

    /// An absolute path to an existing regular `.jsonl` file. Anything else (a directory, a FIFO that
    /// would block a read, a relative path) is ignored.
    private static func usableHint(_ hint: String) -> URL? {
        guard hint.hasPrefix("/"), hint.hasSuffix(".jsonl"),
              FileStatus.of(path: hint)?.isRegularFile == true
        else { return nil }
        return URL(fileURLWithPath: hint, isDirectory: false)
    }

    /// Session ids come from files other programs write; refuse anything that could leave
    /// the project directory or is not a valid file name.
    private static func isPlausibleSessionID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 200 && !id.contains("/") && !id.utf8.contains(0)
    }
}
