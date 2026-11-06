import Foundation
import HeadroomModel

extension SessionMerger {
    /// Spec §2.5 visibility: never after `SessionEnd`; with a pid, while the process that wrote the
    /// record is alive; without one, while the newest write is younger than `pidlessVisibilityWindow`.
    /// A process runs one session at a time, so when records share a pid (a leftover from before
    /// `/clear`, say) only the most recently written one is kept.
    static func visibleBridgeRecords(
        _ records: [BridgeSessionRecord],
        probe: any ProcessProbing,
        now: Date
    ) -> [BridgeSessionRecord] {
        let visible = records.filter { record in
            guard record.lastEvent != ActivityMapping.sessionEndEvent else { return false }
            if let pid = record.pid { return isRunning(record, pid: pid, probe: probe) }
            guard let seen = record.lastSeenAt else { return false }
            return now.timeIntervalSince(seen) < pidlessVisibilityWindow
        }
        let newestPerPid = Dictionary(
            visible.compactMap { record in record.pid.map { ($0, record) } },
            uniquingKeysWith: newestSeen
        )
        return visible.filter { $0.pid == nil } + newestPerPid.values
    }

    /// `pid` is alive and, when its start time can be told, started before the record's newest
    /// write: a SIGKILLed session skips `SessionEnd` and leaves its files, and a process that got
    /// the pid later cannot have written them. The bridge's `ts` is whole seconds (`date +%s`).
    static func isRunning(_ record: BridgeSessionRecord, pid: Int32, probe: any ProcessProbing) -> Bool {
        guard probe.isAlive(pid: pid) else { return false }
        guard let started = probe.startTime(pid: pid), let written = record.lastSeenAt else { return true }
        return ProcessStart.canHaveWritten(started: started, at: written)
    }

    /// A terminal session from its bridge record. Its activity dates from the last hook event, not from
    /// status line writes (1.1 §14.1): those come every few seconds and would restart a waiting episode.
    static func bridgeSession(_ record: BridgeSessionRecord) -> SessionInfo {
        SessionInfo(
            id: record.sessionId,
            name: SessionNaming.folderName(record.cwd) ?? SessionNaming.untitledTerminal,
            projectPath: record.cwd,
            origin: .terminal,
            activity: ActivityMapping.hookEvent(record.lastEvent, notificationType: record.notificationType),
            activitySince: record.lastEventAt ?? record.lastSeenAt,
            startedAt: nil,
            pid: record.pid,
            transcriptPath: record.transcriptPath,
            context: nil
        )
    }
}
