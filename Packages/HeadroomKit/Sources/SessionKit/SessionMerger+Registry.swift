import Foundation
import HeadroomModel

extension SessionMerger {
    /// Supported entrypoints (spec §2.2) whose process is still running, one entry per session id:
    /// when a stale file and a new one share an id, the most recently updated wins.
    static func liveRegistryEntries(_ registry: [RegistryEntry], probe: any ProcessProbing) -> [RegistryEntry] {
        let live = registry.filter { entry in
            ActivityMapping.isSupportedEntrypoint(entry.entrypoint) && isRunning(entry, probe: probe)
        }
        return Array(Dictionary(live.map { ($0.sessionId, $0) }, uniquingKeysWith: newestUpdated).values)
    }

    /// The entry's pid is alive (spec §2.2) and still belongs to the process that wrote the entry,
    /// not a later one that was given the pid after a crash. With `procStart` the start times must
    /// match (as Claude Code itself checks); without it, the process must have started before the
    /// entry's newest time. When the start time cannot be told, liveness alone decides.
    static func isRunning(_ entry: RegistryEntry, probe: any ProcessProbing) -> Bool {
        guard probe.isAlive(pid: entry.pid) else { return false }
        guard let started = probe.startTime(pid: entry.pid) else { return true }
        if let recorded = entry.processStartedAt {
            return ProcessStart.matches(started, recorded: recorded)
        }
        guard let written = [entry.startedAt, entry.statusUpdatedAt].compactMap({ $0 }).max() else { return true }
        return ProcessStart.canHaveWritten(started: started, at: written)
    }

    /// A registry-backed session. Entrypoint `cli` is a terminal `claude` process, so it gets the
    /// terminal origin while keeping the registry's status and times, and its name unless Claude
    /// Code derived that from the folder (then the folder name, as for any terminal session). Desktop
    /// sessions carry the app's own id for them (`hostSessionId`, 1.1 §14.3).
    static func registrySession(_ entry: RegistryEntry, bridge: BridgeSessionRecord?) -> SessionInfo {
        let cwd = entry.cwd ?? bridge?.cwd
        let isTerminal = entry.entrypoint == ActivityMapping.cliEntrypoint
        var activity = ActivityMapping.registryStatus(
            entry.status, waitingFor: entry.waitingFor, startedAt: entry.startedAt, statusUpdatedAt: entry.statusUpdatedAt
        )
        var activitySince = entry.statusUpdatedAt
        if let notifiedAt = pendingNotificationTime(
            bridge, after: entry.statusUpdatedAt, registryReportsWaits: ActivityMapping.registryReportsWaits(entry)
        ) {
            activity = .waitingForInput
            activitySince = notifiedAt
        }
        return SessionInfo(
            id: entry.sessionId,
            name: SessionNaming.registryTitle(entry.name, source: entry.nameSource)
                ?? SessionNaming.folderName(cwd) ?? SessionNaming.untitled,
            projectPath: cwd,
            origin: isTerminal ? .terminal : .desktop,
            activity: activity,
            activitySince: activitySince,
            startedAt: entry.startedAt,
            pid: entry.pid,
            transcriptPath: bridge?.transcriptPath,
            context: nil,
            desktopSessionID: isTerminal ? nil : entry.hostSessionId
        )
    }

    /// Spec §2.5, 1.1 §14.1: a hook `Notification` of a needs-you type newer than the registry's
    /// status means the session is waiting even if the registry has not caught up. Returns its time.
    ///
    /// The hook's `ts` is whole epoch seconds (`date +%s`) while the registry's time has
    /// milliseconds, so the notification happened somewhere in `ts ..< ts + 1 s`: it counts as
    /// newer unless that whole second lies at or before the status time. When the registry reports
    /// waits itself (`registryReportsWaits`), a status written at or after the notification's second
    /// already covers it: a question answered within that second must not stay "needs you".
    private static func pendingNotificationTime(
        _ bridge: BridgeSessionRecord?,
        after statusTime: Date?,
        registryReportsWaits: Bool
    ) -> Date? {
        guard let bridge,
              ActivityMapping.hookEvent(bridge.lastEvent, notificationType: bridge.notificationType) == .waitingForInput,
              let eventTime = bridge.lastEventAt
        else { return nil }
        if let statusTime {
            let covered = registryReportsWaits ? eventTime : eventTime.addingTimeInterval(hookTimestampResolution)
            if covered <= statusTime { return nil }
        }
        return eventTime
    }

    /// The bridge stamps hook records with whole seconds (spec §2.5).
    static let hookTimestampResolution: TimeInterval = 1

    private static func newestUpdated(_ a: RegistryEntry, _ b: RegistryEntry) -> RegistryEntry {
        let updatedA = a.statusUpdatedAt ?? a.startedAt ?? .distantPast
        let updatedB = b.statusUpdatedAt ?? b.startedAt ?? .distantPast
        if updatedA != updatedB { return updatedA > updatedB ? a : b }
        return a.pid >= b.pid ? a : b
    }
}
