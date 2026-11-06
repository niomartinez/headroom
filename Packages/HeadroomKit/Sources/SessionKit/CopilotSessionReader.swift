#if HEADROOM_COPILOT_CLI
import Foundation
import HeadroomModel

/// Copilot CLI sessions from the records Headroom's Copilot bridge writes, `~/.copilot/headroom/sessions/*.hook.json`
/// (1.1 §4.9). Reads nothing else in the Copilot folder but the names in `logs/`, for liveness.
///
/// Sessions come back with `tool == .copilot`, ids `copilot:<session uuid>`, origin `.terminal`, named after the
/// `cwd` folder and without context. A session is shown while its Copilot process is alive, else while its newest
/// record is under 30 minutes old.
public struct CopilotSessionReader: Sendable {
    public let paths: CopilotPaths
    private let probe: any ProcessProbing

    /// `copilotHome`: the granted Copilot CLI folder (`~/.copilot` or the user's pick). `probe` decides which pids
    /// are alive (tests pass a fake).
    public init(copilotHome: URL, probe: any ProcessProbing = SystemProcessProbe()) {
        self.paths = CopilotPaths(copilotDirectory: copilotHome)
        self.probe = probe
    }

    /// Prefix of the ids of Copilot CLI sessions (1.1 §2.2).
    public static let idPrefix = "copilot:"

    /// The sessions to show, sorted with `sortedForDisplay()`. A missing or unreadable records folder → `[]`.
    ///
    /// Liveness (1.1 §4.9): the session's Copilot CLI process is the first of the record's `pids` that has a
    /// `logs/process-<epochMs>-<pid>.log` started while that process runs (see `copilotProcess`). The session is shown
    /// while that process is alive and started before the record was written. When no pid in the record has a log at
    /// all, it is shown while the record is under 30 minutes old. A process runs one session at a time, so when
    /// records share a process (a session left by `/new`, say) only the most recently written one is kept.
    public func readSessions(now: Date) -> [SessionInfo] {
        let records = readRecords().filter { $0.event != CopilotSessionRecord.sessionEndEvent }
        guard !records.isEmpty else { return [] }
        let logs = Self.processLogs(in: paths.logsDirectory)

        var withProcess: [Int32: CopilotSessionRecord] = [:]
        var withoutProcess: [CopilotSessionRecord] = []
        for record in records {
            if record.event == CopilotSessionRecord.sessionCompletedEvent {
                // A successful desktop turn may shut down its process before the next poll.
                // Retain the idle row briefly so MomentDetector can observe its completion.
                guard let written = record.writtenAt,
                      (0..<SessionMerger.pidlessVisibilityWindow).contains(now.timeIntervalSince(written))
                else { continue }
                withoutProcess.append(record)
                continue
            }
            switch copilotProcess(for: record, logs: logs) {
            case .running(let pid):
                if let other = withProcess[pid], !Self.isNewer(record, than: other) { continue }
                withProcess[pid] = record
            case .exited:
                continue
            case .unknown:
                guard let written = record.writtenAt,
                      now.timeIntervalSince(written) < SessionMerger.pidlessVisibilityWindow
                else { continue }
                withoutProcess.append(record)
            }
        }
        let sessions = withProcess.map { pid, record in Self.session(record, pid: pid) }
            + withoutProcess.map { Self.session($0, pid: nil) }
        return sessions.sortedForDisplay()
    }

    // MARK: - Records

    /// One record per session id in `headroom/sessions`. The id comes from the file's own `session_id` when present,
    /// else from its name; when several files name one id, the newest `ts` wins. Hidden files (the bridge's temp files)
    /// are skipped.
    func readRecords() -> [CopilotSessionRecord] {
        // `contentsOfDirectory(at:)` refuses a directory that is itself a symlink.
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: paths.bridgeSessionsDirectory.resolvingSymlinksInPath(),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var records: [String: CopilotSessionRecord] = [:]
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = file.lastPathComponent
            let suffix = CopilotSessionRecord.fileSuffix
            guard name.hasSuffix(suffix), name.count > suffix.count,
                  let record = CopilotSessionRecord(contentsOf: file, fallbackId: String(name.dropLast(suffix.count)))
            else { continue }
            if let existing = records[record.sessionId], !Self.isNewer(record, than: existing) { continue }
            records[record.sessionId] = record
        }
        return records.values.sorted { $0.sessionId < $1.sessionId }
    }

    /// Written later, or at the same second with the larger id, so results never depend on file order.
    static func isNewer(_ a: CopilotSessionRecord, than b: CopilotSessionRecord) -> Bool {
        let writtenA = a.writtenAt ?? .distantPast
        let writtenB = b.writtenAt ?? .distantPast
        if writtenA != writtenB { return writtenA > writtenB }
        return a.sessionId > b.sessionId
    }

    static func session(_ record: CopilotSessionRecord, pid: Int32?) -> SessionInfo {
        SessionInfo(
            id: idPrefix + record.sessionId,
            name: SessionNaming.folderName(record.cwd) ?? SessionNaming.untitledTerminal,
            projectPath: record.cwd,
            origin: .terminal,
            activity: record.activity,
            activitySince: record.writtenAt,
            startedAt: nil,
            pid: pid,
            transcriptPath: nil,
            context: nil,
            tool: .copilot
        )
    }

    // MARK: - Liveness

    enum CopilotProcess: Equatable {
        /// The session's Copilot CLI process, alive.
        case running(pid: Int32)
        /// Some pid in the record has a Copilot CLI log, but none of them is a live process that wrote the record.
        case exited
        /// No pid in the record has a Copilot CLI log: liveness can't be told.
        case unknown
    }

    /// Copilot CLI names each process's log after its start, `logs/process-<epochMs>-<pid>.log`. A record's pid is its
    /// Copilot process when it is alive and has a log whose `epochMs` is no earlier than 2 s before that process
    /// started (a log left by an earlier process with the same pid is older), and the process started before the
    /// record was written (it wrote it). When the system won't tell a start time, a live pid with a log counts.
    func copilotProcess(for record: CopilotSessionRecord, logs: [Int32: [Date]]) -> CopilotProcess {
        let candidates = record.ancestors.filter { logs[$0.pid] != nil }
        guard !candidates.isEmpty else { return .unknown }
        for candidate in candidates where probe.isAlive(pid: candidate.pid) {
            guard let started = probe.startTime(pid: candidate.pid) else { return .running(pid: candidate.pid) }
            let logStarts = logs[candidate.pid] ?? []
            guard logStarts.contains(where: { $0.timeIntervalSince(started) > -ProcessStart.tolerance }) else { continue }
            if let written = record.writtenAt, !ProcessStart.canHaveWritten(started: started, at: written) { continue }
            return .running(pid: candidate.pid)
        }
        return .exited
    }

    /// The Copilot CLI process logs in `directory` by pid: when each was started. Only the names are read, never the
    /// files. A missing or unreadable folder → `[:]`.
    static func processLogs(in directory: URL) -> [Int32: [Date]] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [:] }
        var logs: [Int32: [Date]] = [:]
        for name in names {
            guard let (started, pid) = processLog(name) else { continue }
            logs[pid, default: []].append(started)
        }
        return logs
    }

    /// `process-<epochMs>-<pid>.log` → (start, pid); anything else → nil.
    static func processLog(_ name: String) -> (Date, Int32)? {
        let prefix = "process-", suffix = ".log"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix), name.count > prefix.count + suffix.count else { return nil }
        let fields = name.dropFirst(prefix.count).dropLast(suffix.count).split(separator: "-", omittingEmptySubsequences: false)
        guard fields.count == 2,
              fields.allSatisfy({ !$0.isEmpty && $0.count <= 16 && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let milliseconds = Double(fields[0]), let pid = Int32(fields[1]), pid > 0
        else { return nil }
        return (Date(timeIntervalSince1970: milliseconds / 1000), pid)
    }
}
#endif
