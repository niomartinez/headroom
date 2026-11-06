import ContextKit
import Foundation
import HeadroomModel

/// Reads the Codex folder (1.1 §3.3–3.5), caching per file between calls so a 2-second poll over unchanged files
/// costs a directory listing and a few `stat`s.
///
/// Each `read(now:)`:
/// 1. lists `thread-writer-locks/`;
/// 2. walks `sessions/` at the first read, then at most every 30 s or when the set of locks changed; between walks
///    it only stats the rollouts that can change what is shown (locked threads, or recent files without locks);
/// 3. stats `session_index.jsonl` and the imports file, re-reading them only when they changed;
/// 4. finds the newest limits reading by event time (§3.4), tail-reading only files that changed;
/// 5. builds the shown sessions (§3.5).
///
/// A final class rather than an actor: `SnapshotBuilder.build` is synchronous and already runs on one task at a
/// time, and an actor would make every poll `async` for no gain. Like `SnapshotBuilder`, it is not thread-safe:
/// call `read` from one task at a time.
public final class CodexReader: CodexReadingProviding, @unchecked Sendable {
    public let paths: CodexPaths
    private let runtime: any CodexRuntimeProbing
    private let fileManager: FileManager

    /// How often `sessions/` is walked at most while the locks don't change.
    static let walkInterval: TimeInterval = 30
    /// Rollouts whose head and tail stay cached (LRU).
    static let cacheCapacity = 64
    /// Tail bytes the limits search may read in one call; the rest of a cold search (e.g. on an API key, where no
    /// file has a reading) continues on the next calls, so no single poll reads for long.
    static let limitsReadBudget: Int64 = 64 * 1_024 * 1_024
    /// A long-running turn can start before the normal tail window. Recover older lifecycle events in bounded
    /// windows, only for live root sessions; unfinished recovery continues on the next poll.
    static let lifecycleReadBudget: Int64 = 32 * 1_024 * 1_024
    /// Codex's own baseline: tokens it leaves out of its context percent (§3.5).
    static let baselineTokens = 12_000
    /// The window assumed when none is known (§3.5); the panel then shows tokens only.
    static let assumedWindow = 258_400
    /// Liveness (§3.5): with locks but no process list, a locked thread is shown while its newest event is this
    /// recent; without a locks folder (older Codex), any thread is.
    static let lockedRecencyWithoutProcesses: TimeInterval = 2 * 3_600
    static let recencyWithoutLocks: TimeInterval = 15 * 60
    /// A shown idle thread whose newest event is older than this is hidden.
    static let idleCap: TimeInterval = 8 * 3_600
    /// A locked thread's rollout that isn't found is looked up again at most this often (its file may not exist
    /// yet: Codex takes the lock first).
    static let lookupRetryInterval: TimeInterval = 10

    /// Every file-system call, counted.
    let files = CodexFileAccess()
    /// The calendar for day folders (local time, §3.2) and the disambiguating start times. Tests set a time zone.
    var calendar: Calendar = .current
    var locale: Locale = .current
    let tailScanner = RolloutTailScanner()

    /// A rollout found by the walk.
    struct RolloutFile {
        var url: URL
        var threadID: String
        var signature: FileSignature
        /// The file's readings, valid while `signature` matches.
        var limits: LimitsMemo?
    }

    struct LimitsMemo {
        var signature: FileSignature
        var readings: [String: RateReading]
        var newestEmptyAt: Date?
        var newestUnrecognizedAt: Date?
    }

    /// A rollout's cached head and tail.
    struct CachedRollout {
        var signature: FileSignature
        /// Read once per inode; nil when the head isn't a complete `session_meta`.
        var meta: SessionMeta?
        var metaRead: Bool
        var tail: RolloutTail
        var resumeOffset: Int64
        var historyEnd: Int64?
    }

    enum Locks: Equatable {
        /// No `thread-writer-locks/` (older Codex), or it can't be listed.
        case missing
        case present(Set<String>)
    }

    /// Path → rollout, from the last walk plus lookups since.
    private(set) var index: [String: RolloutFile] = [:]
    private var byThread: [String: [String]] = [:]
    private var lastWalk: Date?
    private var lastLocks: Locks?
    private var sessionsUnreadable = false
    private var lookups: [String: Date] = [:]
    private var cache = LRUCache<String, CachedRollout>(capacity: CodexReader.cacheCapacity)
    private var sessionIndex = SessionIndexCache()
    private var importsCache = ImportsCache()
    private var importsSeen: [String: Date] = [:]
    private var hold = UnrecognizedHold()
    /// Whether the limits must be searched again (files changed, or the last search ran out of budget).
    private var limitsDirty = true
    private var best: [String: RateReading] = [:]
    private var newestEmptyAt: Date?
    private var newestUnrecognizedAt: Date?
    /// Rollout tail bytes read so far (tests: appended-bytes reads, never a whole file).
    private(set) var tailBytesRead: Int64 = 0
    private var lifecycleBytesRemaining: Int64 = 0

    /// `codexHome`: the granted Codex folder (`~/.codex` or the user's pick). `runtime` decides liveness (tests
    /// pass a fake).
    public init(codexHome: URL, runtime: any CodexRuntimeProbing, fileManager: FileManager = .default) {
        self.paths = CodexPaths(codexDirectory: codexHome)
        self.runtime = runtime
        self.fileManager = fileManager
    }

    public func read(now: Date) -> CodexReading {
        lifecycleBytesRemaining = Self.lifecycleReadBudget
        let locks = listLocks()
        if lastWalk.map({ now.timeIntervalSince($0) >= Self.walkInterval || now < $0 }) ?? true || locks != lastLocks {
            walk(now: now)
        } else {
            restatWatchedFiles(locks: locks, now: now)
        }
        lastLocks = locks
        guard !sessionsUnreadable else {
            best = [:]
            newestEmptyAt = nil
            newestUnrecognizedAt = nil
            let usage = hold.resolve(usage: ToolUsage(tool: .codex, status: .noActivity), newestIsUnrecognized: false, now: now)
            return CodexReading(usage: usage.usage, sessions: [], issues: [.codexSessionsUnreadable])
        }
        sessionIndex.refresh(paths.sessionIndexFile, files: files, reader: tailScanner.reader)
        importsCache.refresh(paths.importsFile, files: files)
        if importsCache.imports != importsSeen {
            importsSeen = importsCache.imports
            limitsDirty = true
        }
        if limitsDirty { searchLimits() }

        // A known empty reading (no windows) is recognized too: an unrecognized one older than it doesn't matter.
        let newestRecognized = (best.values.map(\.observedAt) + [newestEmptyAt].compactMap { $0 }).max()
        let newestIsUnrecognized = newestUnrecognizedAt.map { unrecognized in
            newestRecognized.map { unrecognized > $0 } ?? true
        } ?? false
        let resolved = hold.resolve(usage: CodexLimits.usage(from: best), newestIsUnrecognized: newestIsUnrecognized, now: now)
        return CodexReading(
            usage: resolved.usage.rolledOver(now: now),
            sessions: sessions(now: now, locks: locks),
            issues: resolved.issue ? [.codexUsageUnrecognized] : []
        )
    }

    // MARK: - Discovery (§3.3)

    func listLocks() -> Locks {
        guard case .entries(let entries) = files.list(paths.writerLocksDirectory) else { return .missing }
        return .present(Set(entries.compactMap { ThreadID.fromLockName($0.name) }))
    }

    /// Lists `sessions/YYYY/MM/DD/` (any three levels) for rollouts and stats each one.
    private func walk(now: Date) {
        lastWalk = now
        lookups = [:]
        let top: [DirectoryListing.Entry]
        switch files.list(paths.sessionsDirectory) {
        case .missing:
            replaceIndex(with: [:], unreadable: false)
            return
        case .unreadable:
            replaceIndex(with: [:], unreadable: true)
            return
        case .entries(let entries):
            top = entries
        }
        var found: [(url: URL, threadID: String)] = []
        func visit(_ directory: URL, _ entries: [DirectoryListing.Entry], depth: Int) {
            for entry in entries {
                let url = directory.appendingPathComponent(entry.name, isDirectory: entry.isDirectory)
                if let name = RolloutFileName(entry.name) {
                    found.append((url, name.threadID))
                } else if entry.isDirectory, depth < 3, case .entries(let children) = files.list(url) {
                    visit(url, children, depth: depth + 1)
                }
            }
        }
        visit(paths.sessionsDirectory, top, depth: 0)
        var next: [String: RolloutFile] = [:]
        for (url, threadID) in found {
            guard let signature = files.signature(of: url), signature.isRegularFile else { continue }
            var file = index[url.path] ?? RolloutFile(url: url, threadID: threadID, signature: signature)
            file.signature = signature
            next[url.path] = file
        }
        replaceIndex(with: next, unreadable: false)
    }

    private func replaceIndex(with next: [String: RolloutFile], unreadable: Bool) {
        let changed = next.count != index.count
            || next.contains { path, file in index[path]?.signature != file.signature }
        if changed || unreadable != sessionsUnreadable { limitsDirty = true }
        index = next
        sessionsUnreadable = unreadable
        byThread = [:]
        for (path, file) in next { byThread[file.threadID, default: []].append(path) }
    }

    /// Between walks, stats only the rollouts that can change what is shown: the locked threads', or without a
    /// locks folder the ones modified in the last 15 minutes.
    private func restatWatchedFiles(locks: Locks, now: Date) {
        let paths: [String]
        switch locks {
        case .present(let ids):
            paths = ids.compactMap { newestPath(threadID: $0) }
        case .missing:
            paths = index.filter { now.timeIntervalSince($0.value.signature.modified) < Self.recencyWithoutLocks }.map(\.key)
        }
        for path in paths {
            guard var file = index[path] else { continue }
            guard let signature = files.signature(of: file.url), signature.isRegularFile else {
                index[path] = nil
                byThread[file.threadID]?.removeAll { $0 == path }
                limitsDirty = true
                continue
            }
            if signature != file.signature {
                file.signature = signature
                index[path] = file
                limitsDirty = true
            }
        }
    }

    /// The thread's rollout with the newest modification time, if known.
    private func newestPath(threadID: String) -> String? {
        byThread[threadID]?.max { (index[$0]?.signature.modified ?? .distantPast) < (index[$1]?.signature.modified ?? .distantPast) }
    }

    /// Finds a thread's rollout without a walk (§3.5): its UUIDv7 time gives the local day folder; the neighbouring
    /// days cover midnight and time zone changes. Adds what it finds to the index.
    func locateRollout(threadID: String) -> RolloutFile? {
        guard let created = ThreadID.creationDate(threadID) else { return nil }
        var found: [RolloutFile] = []
        for dayOffset in [0, -1, 1] {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: created) else { continue }
            let folder = paths.sessionsDayDirectory(for: day, calendar: calendar)
            guard case .entries(let entries) = files.list(folder) else { continue }
            for entry in entries where RolloutFileName(entry.name)?.threadID == threadID {
                let url = folder.appendingPathComponent(entry.name)
                if let signature = files.signature(of: url), signature.isRegularFile {
                    found.append(RolloutFile(url: url, threadID: threadID, signature: signature))
                }
            }
            if !found.isEmpty { break }
        }
        for file in found where index[file.url.path] == nil {
            index[file.url.path] = file
            byThread[threadID, default: []].append(file.url.path)
            limitsDirty = true
        }
        return found.max { $0.signature.modified < $1.signature.modified }
    }

    // MARK: - Reading rollouts (§3.3)

    /// The rollout's cached head and tail, reading only what changed: nothing when `known` matches the cache, the
    /// appended bytes when the file only grew, else the tail again. The head is read once per inode, and only when
    /// `needHead`.
    private func rollout(_ url: URL, known: FileSignature, needHead: Bool) -> (rollout: CachedRollout, bytesRead: Int64)? {
        let path = url.path
        let cached = cache.value(path)
        if let cached, cached.signature == known, cached.metaRead || !needHead,
           !needHead || cached.historyEnd == nil || lifecycleBytesRemaining < Int64(tailScanner.reader.maxWindow) + 1 {
            return (cached, 0)
        }
        let result: (CachedRollout, Int64)? = files.withOpenFile(url) { descriptor, signature in
            var entry: CachedRollout
            var bytesRead: Int64 = 0
            if let cached, cached.signature == signature {
                entry = cached
            } else if let cached, signature.isAppend(to: cached.signature) {
                let scanned = tailScanner.scan(
                    descriptor: descriptor, from: cached.resumeOffset, size: signature.size,
                    previousRequest: cached.tail.inputRequest
                )
                entry = cached
                entry.tail.merge(newer: scanned.tail)
                if scanned.tail.lifecycle != nil {
                    entry.historyEnd = nil
                } else if let historyEnd = scanned.historyEnd {
                    // More than one tail window arrived between polls: recover the gap as well.
                    entry.historyEnd = historyEnd
                }
                entry.resumeOffset = scanned.scan.resumeOffset
                entry.signature = signature
                bytesRead = scanned.scan.bytesRead
            } else {
                let scanned = tailScanner.scan(descriptor: descriptor, size: signature.size)
                let keepsHead = cached.map { $0.signature.inode == signature.inode && $0.metaRead } ?? false
                entry = CachedRollout(
                    signature: signature,
                    meta: keepsHead ? cached?.meta : nil,
                    metaRead: keepsHead,
                    tail: scanned.tail,
                    resumeOffset: scanned.scan.resumeOffset,
                    historyEnd: scanned.tail.lifecycle == nil ? scanned.historyEnd : nil
                )
                bytesRead = scanned.scan.bytesRead
            }
            if needHead, !entry.metaRead {
                entry.meta = RolloutHeadReader.meta(descriptor: descriptor)
                entry.metaRead = true
            }
            if needHead, entry.meta?.isRootNativeThread == true {
                while let end = entry.historyEnd, lifecycleBytesRemaining >= Int64(tailScanner.reader.maxWindow) + 1 {
                    let older = tailScanner.scan(descriptor: descriptor, size: end)
                    entry.tail.merge(newer: older.tail)
                    bytesRead += older.scan.bytesRead
                    lifecycleBytesRemaining -= older.scan.bytesRead
                    entry.historyEnd = older.tail.lifecycle == nil ? older.historyEnd : nil
                }
            } else if needHead {
                entry.historyEnd = nil
            }
            return (entry, bytesRead)
        }
        guard let (entry, bytesRead) = result else {
            cache.remove(path)
            return nil
        }
        tailBytesRead += bytesRead
        cache.set(path, entry)
        return (entry, bytesRead)
    }

    // MARK: - Limits (§3.4)

    /// The newest reading per bucket, by the event's own timestamp: rollouts are rewritten, which bumps old files'
    /// modification times, so files are only an order to search in. Newest-modified first; once a file's
    /// modification time is more than a second older than the best `codex` reading, no older file can hold a newer
    /// one (a file's modification time is never earlier than its last event). Imported threads are left out.
    /// Each file's readings are kept while its signature holds, so only changed files are read again.
    private func searchLimits() {
        let imports = importsCache.imports
        var best: [String: RateReading] = [:]
        var newestEmpty: Date?
        var newestUnrecognized: Date?
        func fold(_ memo: LimitsMemo) {
            for (id, reading) in memo.readings where reading.observedAt > (best[id]?.observedAt ?? .distantPast) {
                best[id] = reading
            }
            if let at = memo.newestEmptyAt, at > (newestEmpty ?? .distantPast) {
                newestEmpty = at
            }
            if let at = memo.newestUnrecognizedAt, at > (newestUnrecognized ?? .distantPast) {
                newestUnrecognized = at
            }
        }
        var candidates: [RolloutFile] = []
        for file in index.values where imports[file.threadID] == nil {
            if let memo = file.limits, memo.signature == file.signature {
                fold(memo)
            } else {
                candidates.append(file)
            }
        }
        candidates.sort { $0.signature.modified > $1.signature.modified }
        var budget = Self.limitsReadBudget
        var finished = true
        for file in candidates {
            if let main = best[RateReading.mainBucket], file.signature.modified < main.observedAt.addingTimeInterval(-1) {
                break
            }
            guard budget > 0 else {
                finished = false
                break
            }
            let path = file.url.path
            guard let (rollout, bytesRead) = rollout(file.url, known: file.signature, needHead: false) else {
                index[path]?.limits = LimitsMemo(signature: file.signature, readings: [:])
                continue
            }
            budget -= bytesRead
            let memo = LimitsMemo(
                signature: rollout.signature,
                readings: rollout.tail.readings,
                newestEmptyAt: rollout.tail.newestEmptyAt,
                newestUnrecognizedAt: rollout.tail.newestUnrecognizedAt
            )
            index[path]?.signature = rollout.signature
            index[path]?.limits = memo
            fold(memo)
        }
        self.best = best
        newestEmptyAt = newestEmpty
        newestUnrecognizedAt = newestUnrecognized
        limitsDirty = !finished
    }

    // MARK: - Sessions (§3.5)

    private func sessions(now: Date, locks: Locks) -> [SessionInfo] {
        // The threads that may be shown, before asking whether Codex runs (a process list per poll otherwise).
        var files: [RolloutFile] = []
        switch locks {
        case .present(let ids):
            for id in ids.sorted() {
                if let path = newestPath(threadID: id), let file = index[path] {
                    files.append(file)
                } else if lookups[id].map({ now.timeIntervalSince($0) >= Self.lookupRetryInterval || now < $0 }) ?? true {
                    lookups[id] = now
                    if let file = locateRollout(threadID: id) { files.append(file) }
                }
            }
        case .missing:
            // A file's modification time is never earlier than its newest event, so older files can't qualify.
            for threadID in byThread.keys.sorted() {
                guard let path = newestPath(threadID: threadID), let file = index[path],
                      now.timeIntervalSince(file.signature.modified) < Self.recencyWithoutLocks
                else { continue }
                files.append(file)
            }
        }
        guard !files.isEmpty else { return [] }
        let running = runtime.codexRunning()
        if running == false { return [] }
        let maxAge: TimeInterval? = switch locks {
        case .present: running == nil ? Self.lockedRecencyWithoutProcesses : nil
        case .missing: Self.recencyWithoutLocks
        }
        let imports = importsCache.imports
        var shown: [SessionInfo] = []
        for file in files {
            guard let (rollout, _) = rollout(file.url, known: file.signature, needHead: true),
                  let meta = rollout.meta, meta.isRootNativeThread
            else { continue }
            let tail = rollout.tail
            // An imported transcript (e.g. a Claude session) is shown only once the user continued it in Codex.
            if let importedAt = imports[file.threadID] {
                guard let continued = tail.turnContext?.at, continued > importedAt else { continue }
            }
            let newestEvent = tail.newestEventAt ?? meta.timestamp ?? .distantPast
            if let maxAge, now.timeIntervalSince(newestEvent) >= maxAge { continue }
            let working = tail.lifecycle?.isStart == true
            let waitingAt = tail.waitingForInputAt
            if !working, waitingAt == nil, now.timeIntervalSince(newestEvent) > Self.idleCap { continue }
            shown.append(SessionInfo(
                id: "codex:\(file.threadID)",
                name: sessionIndex.title(threadID: file.threadID) ?? Self.folderName(meta.cwd) ?? "Codex",
                projectPath: meta.cwd,
                origin: meta.isTerminal ? .terminal : .desktop,
                activity: waitingAt != nil ? .waitingForInput : (working ? .working : .idle),
                activitySince: waitingAt ?? tail.lifecycle?.at ?? newestEvent,
                startedAt: meta.timestamp,
                pid: nil,
                transcriptPath: nil,
                context: Self.context(tail),
                tool: .codex
            ))
        }
        return disambiguated(shown)
    }

    /// The context row (§3.5): the newest `token_count` with `info`; Codex's own percent with a 12,000-token
    /// baseline. The window comes from `info` (exact), else from `task_started`, else 258,400 assumed.
    static func context(_ tail: RolloutTail) -> ContextUsage? {
        guard let sample = tail.context else { return nil }
        let window: Int
        var exact = false
        var assumed = false
        if let fromInfo = sample.window {
            window = fromInfo
            exact = true
        } else if let started = tail.startedWindow?.value {
            window = started
        } else {
            window = assumedWindow
            assumed = true
        }
        return ContextUsage(
            usedTokens: sample.usedTokens,
            windowTokens: window,
            model: tail.model,
            windowIsExact: exact,
            observedAt: sample.at,
            windowIsAssumed: assumed,
            baselineTokens: baselineTokens
        )
    }

    /// The last component of `cwd`, if any.
    static func folderName(_ cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    /// Rows sharing a name get their start time: `release · 2:14 PM` (§3.5).
    func disambiguated(_ sessions: [SessionInfo]) -> [SessionInfo] {
        let counts = Dictionary(grouping: sessions, by: \.name).mapValues(\.count)
        return sessions.map { session in
            guard counts[session.name, default: 0] > 1, let started = session.startedAt else { return session }
            var session = session
            session.name += " · " + shortTime(started)
            return session
        }
    }

    func shortTime(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        )
    }
}
