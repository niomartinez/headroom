import Foundation
import HeadroomModel

/// Spec §3.4 and 1.1 §6.2: turns the change from one snapshot to the next into pill moments, with guards against the
/// false positives a poller would otherwise produce.
///
/// Moments don't say how many tools are tracked: whether a limit moment names its tool ("Codex weekly at 90%") is
/// decided where it is shown, from the snapshot on screen (`HeadroomSnapshot.isMultiTool`, i.e. its
/// `trackedTools.count`), as `Moment` documents.
public enum MomentDetector {
    /// A session must have been working at least this long for going idle to count as finishing.
    static let minimumWorkingDuration: TimeInterval = 5
    /// Limit thresholds, highest first: one step announces only the highest one it crossed.
    static let limitThresholds = [100, 90]
    /// A limit rising more than this in one step is a data correction (e.g. after an inferred rollover set it to
    /// 0 too early), not usage crossing a threshold.
    static let largestCrossingStep: Double = 25
    /// The tools whose limits come as `toolLimitCrossed`, in display order. Claude's come as `limitCrossed`.
    static let otherTools: [ToolID] = [.codex, .copilot]

    /// Session moments first (in display order), then at most one `limitCrossed` per Claude limit kind, then at most
    /// one `toolLimitCrossed` per (tool, window): Codex, then Copilot, each longest window first.
    ///
    /// - No moments without a previous snapshot (launch, or access just changed).
    /// - `sessionFinished`: the same session (any tool) was working for ≥ 5 s (its `activitySince` in `previous` is
    ///   at least 5 s before `current.generatedAt`, or unknown) and is now idle. A Codex turn completing is one.
    /// - `sessionNeedsInput`: the same session is now waiting and wasn't before.
    /// - Sessions that appeared or disappeared produce nothing.
    /// - `limitCrossed`: both snapshots have the reading, the current one is a newer observation, it went from
    ///   below the threshold to at or above it, and rose no more than 25 points.
    /// - `toolLimitCrossed`: the same rules per (tool, window), for the tool's main limits (never `otherBuckets`,
    ///   which a moment can't name), with a known percent on both sides. None when the tool's plan or account
    ///   changed between the snapshots (`planName`, `account`, or the limit's `allowance` or `unit`): another
    ///   account's usage, or the same usage measured against another allowance, crossed nothing just now. Copilot
    ///   reaching 100 is `toolLimitCrossed(tool: .copilot, window: .monthly, percent: 100)`, shown as "used up".
    ///
    /// Doesn't know which desktop account Claude's readings belong to: callers that poll a `SnapshotBuilder` use
    /// `moments(previous:previousDesktopAccount:current:currentDesktopAccount:)` instead.
    public static func moments(previous: HeadroomSnapshot?, current: HeadroomSnapshot) -> [Moment] {
        moments(previous: previous, previousDesktopAccount: nil, current: current, currentDesktopAccount: nil)
    }

    /// `moments(previous:current:)`, knowing each snapshot's desktop account: `SnapshotBuilder.desktopAccount`
    /// right after the build that made it.
    ///
    /// When the two accounts are known and differ, a limit whose readings both came from the desktop app yields
    /// no `limitCrossed`. Switching accounts in the desktop app (spec §2.1) swaps in the other account's usage,
    /// which crossed no threshold just now, however close the two values are. Nil = unknown: compared as before.
    /// Terminal readings carry no account and are always compared. Codex and Copilot carry their own plan and
    /// account in the snapshot, so the desktop account doesn't affect their moments.
    public static func moments(
        previous: HeadroomSnapshot?,
        previousDesktopAccount: String?,
        current: HeadroomSnapshot,
        currentDesktopAccount: String?
    ) -> [Moment] {
        guard let previous else { return [] }
        let accountSwitched = previousDesktopAccount != nil && currentDesktopAccount != nil
            && previousDesktopAccount != currentDesktopAccount
        return sessionMoments(from: previous, to: current)
            + LimitKind.allCases.compactMap {
                limitMoment($0, from: previous.plan, to: current.plan, desktopAccountSwitched: accountSwitched)
            }
            + otherTools.flatMap { toolLimitMoments($0, from: previous, to: current) }
    }

    private static func sessionMoments(from previous: HeadroomSnapshot, to current: HeadroomSnapshot) -> [Moment] {
        let before = Dictionary(previous.sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return current.sessions.compactMap { session in
            guard let old = before[session.id] else { return nil }
            switch (old.activity, session.activity) {
            case (.working, .idle) where workedLongEnough(old, by: current.generatedAt):
                return .sessionFinished(sessionID: session.id, name: session.name)
            case (.working, .waitingForInput), (.idle, .waitingForInput):
                return .sessionNeedsInput(sessionID: session.id, name: session.name)
            default:
                return nil
            }
        }
    }

    private static func workedLongEnough(_ session: SessionInfo, by time: Date) -> Bool {
        guard let since = session.activitySince else { return true }
        return since <= time.addingTimeInterval(-minimumWorkingDuration)
    }

    private static func limitMoment(
        _ kind: LimitKind, from previous: PlanUsage, to current: PlanUsage, desktopAccountSwitched: Bool
    ) -> Moment? {
        guard let old = previous.reading(kind), let new = current.reading(kind),
              new.observedAt > old.observedAt,
              !(desktopAccountSwitched && old.source == .desktopApp && new.source == .desktopApp)
        else { return nil }
        return crossedThreshold(from: old.usedPercent, to: new.usedPercent).map {
            .limitCrossed(kind: kind, percent: $0)
        }
    }

    /// One `toolLimitCrossed` per window of `tool` that crossed, in the current snapshot's limit order.
    private static func toolLimitMoments(
        _ tool: ToolID, from previous: HeadroomSnapshot, to current: HeadroomSnapshot
    ) -> [Moment] {
        guard let before = previous.usage(for: tool), let after = current.usage(for: tool),
              before.planName == after.planName, before.account == after.account
        else { return [] }
        var windows = Set<WindowKind>()
        return after.limits.compactMap { new in
            guard windows.insert(new.window).inserted,
                  let old = before.limit(new.window),
                  new.observedAt > old.observedAt,
                  new.allowance == old.allowance, new.unit == old.unit,
                  let oldPercent = old.usedPercent, let newPercent = new.usedPercent
            else { return nil }
            return crossedThreshold(from: oldPercent, to: newPercent).map {
                .toolLimitCrossed(tool: tool, window: new.window, percent: $0)
            }
        }
    }

    /// The highest threshold `old → new` went from below to at or above, unless it rose more than 25 points.
    private static func crossedThreshold(from old: Double, to new: Double) -> Int? {
        guard new - old <= largestCrossingStep else { return nil }
        return limitThresholds.first { threshold in
            old < Double(threshold) && Double(threshold) <= new
        }
    }
}
