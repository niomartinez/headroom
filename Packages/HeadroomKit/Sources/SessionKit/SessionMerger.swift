import Foundation
import HeadroomModel

public enum SessionMerger {
    /// Spec §2.5: a terminal session without a known pid stays visible this long after its newest write.
    public static let pidlessVisibilityWindow: TimeInterval = 30 * 60

    /// Filters, maps and merges both sources into display-ready sessions (context left nil),
    /// sorted with `sortedForDisplay()`.
    ///
    /// The registry is the authority for every session it lists (spec §2.5 "registry data wins"):
    /// a bridge record whose id or pid belongs to an excluded SDK entry is never shown (that
    /// process is a plugin's), and one whose id or pid belongs to a shown registry session only
    /// enriches that session. Registry entries for dead pids claim nothing by id, so their bridge
    /// records are judged as terminal sessions. "Dead" includes a pid now held by a later process
    /// (see `isRunning`): such an entry claims no pid either.
    public static func merge(
        registry: [RegistryEntry],
        bridge: [BridgeSessionRecord],
        probe: any ProcessProbing,
        now: Date
    ) -> [SessionInfo] {
        let bridgeById = Dictionary(bridge.map { ($0.sessionId, $0) }, uniquingKeysWith: newestSeen)

        let registered = liveRegistryEntries(registry, probe: probe).map { entry in
            registrySession(entry, bridge: bridgeById[entry.sessionId])
        }

        let excluded = registry.filter { !ActivityMapping.isSupportedEntrypoint($0.entrypoint) }
        let claimedIds = Set(excluded.map(\.sessionId)).union(registered.map(\.id))
        // Only an excluded entry whose process still holds its pid claims that pid: a plugin entry
        // left behind by a killed SDK process must not hide a `claude` that was later given the pid.
        let claimedPids = Set(registered.compactMap(\.pid))
            .union(excluded.filter { isRunning($0, probe: probe) }.map(\.pid))
        let unclaimed = bridgeById.values.filter { record in
            !claimedIds.contains(record.sessionId) && !(record.pid.map(claimedPids.contains) ?? false)
        }
        let bridgeOnly = visibleBridgeRecords(unclaimed, probe: probe, now: now).map(bridgeSession)

        return (registered + bridgeOnly).sortedForDisplay()
    }

    /// The record written to most recently; ties go to the larger id so results never depend on input order.
    static func newestSeen(_ a: BridgeSessionRecord, _ b: BridgeSessionRecord) -> BridgeSessionRecord {
        let seenA = a.lastSeenAt ?? .distantPast
        let seenB = b.lastSeenAt ?? .distantPast
        if seenA != seenB { return seenA > seenB ? a : b }
        return a.sessionId >= b.sessionId ? a : b
    }
}
