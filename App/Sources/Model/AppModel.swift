import AppKit
import Foundation
import HeadroomModel
import HeadroomSamples
import HeadroomStore
import HeadroomUI
import Observation
import SetupKit

/// The app's live state: polls every 2 s, publishes the snapshot, and turns snapshot changes
/// into pill moments (spec §1.1, §3.4, §4). In sample data mode (`SampleDataMode`) it publishes a
/// made-up snapshot instead, reads no files on the poll and shows no moments.
///
/// 1.1: builds the snapshot for the tools the user tracks (Settings › Tools, §7), with Copilot's usage from
/// `CopilotAccount`; keeps "Rings show", "One gauge per tool" and the widget setting; hands every snapshot it shows to
/// the widgets (`WidgetPublisher`, §5.4). Keeps which waits the user saw or dismissed (`NeedsYouState`, §14.4): the
/// pill, panel, VoiceOver and widgets show `presentation`, with dismissed waits read as idle.
@MainActor
@Observable
final class AppModel {
    static let pollInterval: Duration = .seconds(2)

    private(set) var snapshot: HeadroomSnapshot
    /// Advances with every poll so relative times ("2m ago", staleness) stay current.
    private(set) var now: Date
    /// The moment the pill is showing, if any.
    private(set) var currentMoment: Moment?
    /// nil until the first check, or while `~/.claude` isn't readable.
    private(set) var bridgeState: BridgeInstallState?
    /// Not connected, but files an earlier Disconnect couldn't delete are still there
    /// (`SnapshotWorker.Result.hasBridgeLeftovers`); Disconnect deletes them.
    private(set) var hasBridgeLeftovers = false
    /// A Connect / Disconnect is running.
    private(set) var isChangingBridge = false
    private(set) var showMoments: Bool
    /// Sample data mode; see `SampleDataMode`.
    private(set) var sampleData: SampleDataMode
    /// The last snapshot built from real files, whatever `snapshot` shows. Nil until the first poll.
    private(set) var lastRealSnapshot: HeadroomSnapshot?

    /// Settings › Tools: which tools are tracked.
    private(set) var tracking: ToolTracking
    /// "Rings show" as saved (Automatic, or a tool that may not be tracked right now).
    private(set) var ringsChoice: RingsChoice
    /// "One gauge per tool".
    private(set) var gaugePerTool: Bool
    private(set) var menuBarLayout: MenuBarLayout
    /// "Show session names in widgets".
    private(set) var widgetShowsSessionNames: Bool
    /// Which waits the user saw or dismissed, "Keep “needs you” in the menu bar until I look", and what the pill
    /// holds while the panel is open (1.1 §14.4).
    private(set) var needsYou: NeedsYouState
    /// Sessions that finished and haven't been reviewed: the panel's Just finished (1.1.1).
    private(set) var finished: FinishedTracker
    /// Connect Copilot CLI's state; nil until the Copilot CLI folder has been read.
    private(set) var copilotCLIState: CopilotCLIState?
    /// Not connected, but files an earlier Disconnect couldn't delete are still in `~/.copilot`.
    private(set) var hasCopilotCLILeftovers = false
    /// A Connect / Disconnect Copilot CLI is running.
    private(set) var isChangingCopilotCLI = false

    let access: AccessManager
    /// GitHub Copilot usage: sign-in, plan and polling (1.1 §4).
    let copilot: CopilotAccount

    @ObservationIgnored private let worker: SnapshotWorker
    @ObservationIgnored private let defaults: UserDefaults
    /// False for `--render-live`: the menu bar app owns the saved marks.
    @ObservationIgnored private let persistsMarks: Bool
    /// The app a session runs in (its terminal or editor, the Copilot app), for Just finished's "looked at it there"
    /// (1.1.2). Set by `AppCoordinator`; nil for `--render-live`.
    @ObservationIgnored var hostBundleID: (@MainActor (SessionInfo) -> String?)?
    /// Nil for `--render-live`.
    @ObservationIgnored private let widgets: WidgetPublisher?
    /// The widget work queued last: each publish waits for the one before, so the file never goes back in time.
    @ObservationIgnored private var widgetTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var momentTask: Task<Void, Never>?
    @ObservationIgnored private var momentQueue = MomentQueue()
    /// Drops an older poll that finishes after a newer one was applied.
    @ObservationIgnored private var pollOrdering = PollOrdering()
    /// The last snapshot, the Claude app account its desktop readings belong to, and the access and sources it
    /// was built with; moments compare against it.
    @ObservationIgnored private var previous: (
        snapshot: HeadroomSnapshot, desktopAccount: String?, paths: ClaudePaths, access: AccessState,
        sources: SourceSelection
    )?

    /// `liveRender` (`--render-live`, which runs beside the menu bar app): real data only, whatever "Show sample data"
    /// says; the widgets' file is never written; and no GitHub request is made, since only the menu bar app's
    /// `CopilotService` may use and refresh the tokens.
    init(access: AccessManager, defaults: UserDefaults = .standard, liveRender: Bool = false) {
        let launch = Date()
        self.access = access
        self.defaults = defaults
        copilot = CopilotAccount.live(defaults: defaults, networking: !liveRender)
        worker = SnapshotWorker(codexAppIsRunning: {
            !NSRunningApplication.runningApplications(withBundleIdentifier: CodexApp.bundleIdentifier).isEmpty
        })
        widgets = liveRender ? nil : WidgetPublisher()
        self.snapshot = .empty(at: launch)
        self.now = launch
        self.showMoments = defaults.bool(forKey: Preferences.showMoments)
        self.sampleData = SampleDataMode(isOn: !liveRender && defaults.bool(forKey: Preferences.showSampleData))
        tracking = ToolTracking(defaults: defaults)
        ringsChoice = RingsChoice(defaults: defaults)
        gaugePerTool = defaults.bool(forKey: Preferences.gaugePerTool)
        menuBarLayout = MenuBarLayout(defaults: defaults)
        widgetShowsSessionNames = defaults.bool(forKey: Preferences.widgetShowsSessionNames)
        // `--render-live` reads the marks but never writes them: the menu bar app owns them.
        needsYou = NeedsYouState(defaults: defaults, persists: !liveRender)
        finished = FinishedTracker(finished: FinishedMarks.decode(defaults.dictionary(forKey: Preferences.justFinished)))
        persistsMarks = !liveRender
        copilot.onConnected = { [weak self] in self?.setTrackCopilot(true) }
        copilot.update(tracked: tracking.copilot, sampleData: sampleData.isOn)
        if sampleData.isOn {
            showSample()
        }
    }

    /// What the panel shows about sample data: the footer while it's on, the offer when there is
    /// no data at all.
    var panelSampleData: PanelSampleData {
        sampleData.panelState(lastReal: lastRealSnapshot, access: access.state)
    }

    /// The tool the rings show now: "Rings show", or Automatic when that tool isn't tracked (1.1 §6.1). The widgets'
    /// Automatic.
    var pillTool: ToolID? {
        RingsTool.resolve(ringsChoice.tool, in: snapshot)
    }

    /// The snapshot as the pill, panel, VoiceOver and widgets show it: dismissed waits read as idle, and who is still
    /// unseen (1.1 §14.4). Sample data is shown as it is.
    var presentation: NeedsYouPresentation {
        needsYou.presentation(of: snapshot, sampleData: sampleData.isOn)
    }

    /// The pill's needs-you rest state, "(!) harbor" (1.1 §14.4); nil in sample data, with moments off or with "Keep
    /// “needs you” in the menu bar until I look" off.
    var pillAttention: NeedsYouAttention? {
        needsYou.pillAttention(presentation, showsMoments: showMoments, sampleData: sampleData.isOn)
    }

    /// The panel's Just finished rows: none in sample data, whose sessions are made up.
    var panelFinishedIDs: Set<String> {
        sampleData.isOn ? [] : finished.ids(in: snapshot.sessions)
    }

    /// "Keep “needs you” in the menu bar until I look".
    var keepNeedsYou: Bool {
        needsYou.keepsInMenuBar
    }

    /// The panel's Codex offer (1.1 §6.3).
    var showsCodexOffer: Bool {
        CodexOffer.shows(tracking: tracking, codexInstalled: access.state.codexInstalled, sampleData: sampleData.isOn)
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        momentTask?.cancel()
        momentTask = nil
        copilot.update(tracked: false, sampleData: sampleData.isOn)
    }

    /// The moment the pill is showing, or else the next one queued (`--render-live`).
    var momentToRender: Moment? {
        LiveRender.momentToRender(current: currentMoment, pending: momentQueue.pending)
    }

    /// One tick of the poll loop: real files, or in sample data mode a sample snapshot for now (after
    /// one real check when the app launched with sample data on).
    func poll() async {
        switch sampleData.pollSource {
        case .realFiles:
            await refresh()
        case .sample:
            showSample()
        case .checkRealStateThenSample:
            // Launched with sample data on: learn the real access and bridge state once.
            await refresh()
            if sampleData.isOn { showSample() }
        }
    }

    /// Reads the real files now instead of waiting for the next tick, e.g. after a grant or a
    /// Connect. The folders are probed on the worker, off the main thread, like every other file
    /// read (spec §4). In sample data mode only the access and bridge states are kept
    /// (Settings shows them); the pill and panel keep the sample snapshot.
    func refresh() async {
        let poll = pollOrdering.begin()
        let epoch = sampleData.epoch
        let check = access.pollCheck(at: poll.startedAt)
        let tracking = tracking
        let result = await worker.refresh(
            check: check,
            tracking: tracking,
            copilot: tracking.copilot ? copilot.snapshotUsage : nil,
            finishedIDs: Set(finished.finished.keys),
            lookUpDesktopApp: access.lookUpDesktopApp,
            lookUpCodexApp: access.lookUpCodexApp,
            now: poll.startedAt
        )
        // A grant (or a re-check for Settings) while this poll ran made it out of date; the poll
        // after it shows the change.
        guard access.isCurrent(result.access) else { return }
        // refresh() can overlap the poll loop; a slower, older poll must not win.
        guard pollOrdering.shouldApply(poll) else { return }
        access.apply(result.access, checkedAt: poll.startedAt)
        applyBridge(result)
        if !sampleData.hasCheckedRealState {
            sampleData.recordRealCheck()
        }
        // Sample data went on (or on and off again) while this poll ran.
        guard sampleData.showsRealSnapshot(fromPollStartedIn: epoch) else { return }
        apply(result, paths: check.paths, access: result.access.state)
    }

    /// Turns sample data mode on or off (Settings, the panel's offer and its "Turn off").
    func setShowSampleData(_ enabled: Bool) {
        guard let change = sampleData.set(enabled) else { return }
        defaults.set(enabled, forKey: Preferences.showSampleData)
        copilot.update(tracked: tracking.copilot, sampleData: enabled)
        if change.clearMoments {
            momentQueue.removeAll()
            show(nil)
        }
        if change.resetMomentBaseline {
            previous = nil
        }
        if enabled {
            showSample()
        } else if let lastRealSnapshot {
            // The last real snapshot until the poll below brings a fresh one.
            snapshot = lastRealSnapshot
            now = Date()
        } else {
            snapshot = .empty(at: Date())
            now = snapshot.generatedAt
        }
        if change.pollNow {
            Task { await poll() }
        }
    }

    /// The made-up snapshot for this moment, true to the real terminal connection.
    private func showSample() {
        let at = Date()
        let connected = lastRealSnapshot?.terminalBridgeConnected ?? false
        snapshot = SampleData(now: at).showcase(terminalConnected: bridgeState.map(Self.isConnected) ?? connected)
        now = at
        publishWidgets(isSample: true)
    }

    /// Installed, or installed with an older script that still reports (as `SnapshotBuilder` has it).
    private static func isConnected(_ state: BridgeInstallState) -> Bool {
        state == .installed || state == .outdated
    }

    func setShowMoments(_ enabled: Bool) {
        showMoments = enabled
        defaults.set(enabled, forKey: Preferences.showMoments)
        if !sampleData.showsMoments(userSetting: enabled) {
            momentQueue.removeAll()
            show(nil)
        }
    }

    func setKeepNeedsYou(_ enabled: Bool) {
        guard enabled != needsYou.keepsInMenuBar else { return }
        needsYou.setKeepsInMenuBar(enabled)
    }

    // MARK: Menu bar and widgets (1.1 §6.1, §6.4)

    func setRingsChoice(_ choice: RingsChoice) {
        guard choice != ringsChoice else { return }
        ringsChoice = choice
        defaults.set(choice.rawValue, forKey: Preferences.ringsTool)
        publishWidgets(isSample: sampleData.isOn)
    }

    func setGaugePerTool(_ enabled: Bool) {
        guard enabled != gaugePerTool else { return }
        gaugePerTool = enabled
        defaults.set(enabled, forKey: Preferences.gaugePerTool)
    }

    func setMenuBarLayout(_ layout: MenuBarLayout) {
        guard layout != menuBarLayout else { return }
        menuBarLayout = layout
        defaults.set(layout.rawValue, forKey: Preferences.menuBarLayout)
    }

    func setWidgetShowsSessionNames(_ enabled: Bool) {
        guard enabled != widgetShowsSessionNames else { return }
        widgetShowsSessionNames = enabled
        defaults.set(enabled, forKey: Preferences.widgetShowsSessionNames)
        publishWidgets(isSample: sampleData.isOn)
    }

    // MARK: Tracked tools (1.1 §6.4, §7)

    func setTrackClaude(_ enabled: Bool) {
        guard enabled != tracking.claude else { return }
        tracking.claude = enabled
        defaults.set(enabled, forKey: Preferences.trackClaude)
        trackingChanged()
    }

    /// Also the Codex offer's answers: Give access (once granted) and Not now.
    func setTrackCodex(_ enabled: Bool) {
        guard tracking.codex != enabled else { return }
        tracking.codex = enabled
        defaults.set(enabled, forKey: Preferences.trackCodex)
        trackingChanged()
    }

    func setTrackCopilot(_ enabled: Bool) {
        guard enabled != tracking.copilot else { return }
        tracking.copilot = enabled
        defaults.set(enabled, forKey: Preferences.trackCopilot)
        copilot.update(tracked: enabled, sampleData: sampleData.isOn)
        trackingChanged()
    }

    /// The Codex offer's Give access (1.1 §6.3): the folder picker, then Codex is tracked once the folder is readable.
    func giveCodexAccess() {
        if access.requestAccess(to: .codex) {
            setTrackCodex(true)
        }
    }

    /// Settings' Grant access for the Codex folder while Codex is still undecided: granting it is a yes.
    func codexAccessGranted() {
        if tracking.codex == nil {
            setTrackCodex(true)
        }
    }

    /// Shows the change now rather than on the next tick.
    private func trackingChanged() {
        Task { await refresh() }
    }

    // MARK: Events

    /// The panel opened: Copilot refreshes a reading older than 5 minutes (1.1 §4.7), and every wait counts as seen
    /// (1.1 §14.4). The pill keeps its rest state until the panel closes; "needs you" moments for those sessions,
    /// showing or queued, are dropped.
    func panelOpened() {
        copilot.panelOpened()
        let shown = pillAttention
        let seen = needsYou.panelOpened(attention: shown, sampleData: sampleData.isOn, now: Date())
        dropNeedsYouMoments(for: seen)
    }

    /// The panel's Refresh button: the folders are probed again, the files read now rather than on the next tick, and
    /// Copilot fetches once whatever its reading's age. Claude's and Codex's numbers can only be as new as the files
    /// their apps last wrote.
    func refreshNow() {
        access.refresh(recheckDesktopApp: true)
        copilot.refreshNow()
        Task { await poll() }
    }

    /// The panel closed: the pill narrows unless something new needs you.
    func panelClosed() {
        needsYou.panelClosed()
    }

    /// "Dismiss" on a Needs you row (1.1 §14.4): this wait leaves the pill's dot and count, VoiceOver's count and
    /// the widgets until the session waits again.
    func dismissNeedsYou(_ id: String) {
        guard !sampleData.isOn, needsYou.dismiss(id, now: Date()) else { return }
        dropNeedsYouMoments(for: [id])
        publishWidgets(isSample: false)
    }

    /// "Dismiss" on a row: a just-finished session moves to Idle, a waiting one leaves Needs you's count.
    func dismissSession(_ id: String) {
        if !reviewFinished(id) {
            dismissNeedsYou(id)
        }
    }

    /// A just-finished session was opened from the panel or dismissed: it moves to Idle. Returns whether it was
    /// in Just finished.
    @discardableResult
    func reviewFinished(_ id: String) -> Bool {
        guard !sampleData.isOn else { return false }
        return changingFinished { $0.review(id) }
    }

    /// "Clear" on Just finished.
    func clearFinished() {
        guard !sampleData.isOn else { return }
        changingFinished { $0.reviewAll() }
    }

    /// Runs `change` on the Just finished marks and saves them when they changed. Returns whether they did.
    @discardableResult
    private func changingFinished(_ change: (inout FinishedTracker) -> Bool) -> Bool {
        var next = finished
        guard change(&next) else { return false }
        finished = next
        if persistsMarks {
            defaults.set(FinishedMarks.encode(next.finished), forKey: Preferences.justFinished)
        }
        return true
    }

    /// "Show in Needs you again" on a dismissed row.
    func undoDismissNeedsYou(_ id: String) {
        guard !sampleData.isOn, needsYou.undoDismiss(id) else { return }
        publishWidgets(isSample: false)
    }

    /// The Mac woke from sleep: the widgets reload with the next snapshot, and Copilot fetches once (1.1 §4.7, §5.4).
    func didWake() {
        if let widgets {
            let previous = widgetTask
            widgetTask = Task {
                await previous?.value
                await widgets.noteWake()
            }
        }
        copilot.didWake()
    }

    // MARK: Terminal bridge (spec §2.6)

    func installBridge() async throws {
        try await changeBridge { try await $0.installBridge(claudeDirectory: $1) }
    }

    func uninstallBridge() async throws {
        try await changeBridge { try await $0.uninstallBridge(claudeDirectory: $1) }
    }

    private func changeBridge(_ change: (SnapshotWorker, URL) async throws -> Void) async throws {
        isChangingBridge = true
        defer { isChangingBridge = false }
        do {
            try await change(worker, access.paths.claudeDirectory)
        } catch {
            await refresh()
            throw error
        }
        await refresh()
    }

    #if HEADROOM_COPILOT_CLI
    // MARK: Copilot CLI (1.1 §4.9)

    /// What Connect (or Disconnect) Copilot CLI would change now, for its dialog.
    func copilotCLIPlan(uninstalling: Bool) async -> [CopilotCLIConsent.Change] {
        let directory = access.copilotDirectory
        return uninstalling
            ? await worker.copilotCLIUninstallPlan(copilotDirectory: directory)
            : await worker.copilotCLIInstallPlan(copilotDirectory: directory)
    }

    /// Connects Copilot CLI and tracks Copilot.
    func installCopilotCLI() async throws {
        try await changeCopilotCLI { try await $0.installCopilotCLI(copilotDirectory: $1) }
        setTrackCopilot(true)
    }

    func uninstallCopilotCLI() async throws {
        try await changeCopilotCLI { try await $0.uninstallCopilotCLI(copilotDirectory: $1) }
    }

    private func changeCopilotCLI(_ change: (SnapshotWorker, URL) async throws -> Void) async throws {
        isChangingCopilotCLI = true
        defer { isChangingCopilotCLI = false }
        do {
            try await change(worker, access.copilotDirectory)
        } catch {
            await refresh()
            throw error
        }
        await refresh()
    }
    #endif

    private func applyBridge(_ result: SnapshotWorker.Result) {
        if result.bridgeState != bridgeState {
            bridgeState = result.bridgeState
        }
        if result.hasBridgeLeftovers != hasBridgeLeftovers {
            hasBridgeLeftovers = result.hasBridgeLeftovers
        }
        if result.copilotCLIState != copilotCLIState {
            copilotCLIState = result.copilotCLIState
        }
        if result.hasCopilotCLILeftovers != hasCopilotCLILeftovers {
            hasCopilotCLILeftovers = result.hasCopilotCLILeftovers
        }
    }

    private func apply(_ result: SnapshotWorker.Result, paths: ClaudePaths, access accessState: AccessState) {
        // Sessions and limits appearing because access, paths or the tracked tools changed are not events.
        let comparable = previous.flatMap {
            $0.paths == paths && $0.access == accessState && $0.sources == result.sources ? $0 : nil
        }
        // Switching accounts in the Claude app swaps in the other account's usage; that crossed no
        // threshold (spec §2.1).
        let moments = MomentDetector.moments(
            previous: comparable?.snapshot,
            previousDesktopAccount: comparable?.desktopAccount,
            current: result.snapshot,
            currentDesktopAccount: result.desktopAccount
        )
        previous = (result.snapshot, result.desktopAccount, paths, accessState, result.sources)

        snapshot = result.snapshot
        lastRealSnapshot = result.snapshot
        now = Date()
        needsYou.update(sessions: result.snapshot.sessions, now: now)
        let finishedBefore = finished.finished
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let hostBundleID = hostBundleID
        changingFinished {
            $0.update(sessions: result.snapshot.sessions, moments: moments, now: now)
            // Looked at in its own app, as an answered wait leaves Needs you (1.1.2).
            $0.reviewViewed(
                sessions: result.snapshot.sessions, signals: result.views, frontmost: frontmost,
                hostBundleID: { hostBundleID?($0) }, now: now
            )
            return $0.finished != finishedBefore
        }
        publishWidgets(isSample: false)

        if sampleData.showsMoments(userSetting: showMoments), let next = momentQueue.enqueue(moments) {
            show(next)
        }
    }

    /// Hands the snapshot on screen to the widgets, off the main thread (1.1 §5.4), with dismissed waits read as idle
    /// (§14.4). `WidgetPublisher` decides whether that writes the file or reloads the widgets; without an App Group it
    /// does nothing.
    private func publishWidgets(isSample: Bool) {
        guard let widgets else { return }
        let snapshot = presentation.snapshot
        let pillTool = pillTool
        let showsNames = widgetShowsSessionNames
        let at = Date()
        let previous = widgetTask
        widgetTask = Task {
            await previous?.value
            await widgets.publish(snapshot, isSample: isSample, pillTool: pillTool, showsNames: showsNames, now: at)
        }
    }

    /// Drops the "needs you" moments, showing or queued, of sessions the user has just seen or dismissed.
    private func dropNeedsYouMoments(for ids: Set<String>) {
        guard !ids.isEmpty else { return }
        if momentQueue.removeAll(where: { $0.needsInputSessionID.map(ids.contains) ?? false }) {
            show(momentQueue.current)
        }
    }

    /// Shows `moment` for `MomentQueue.displayDuration`, then the next queued one.
    private func show(_ moment: Moment?) {
        momentTask?.cancel()
        currentMoment = moment
        guard moment != nil else { return }
        momentTask = Task { [weak self] in
            try? await Task.sleep(for: MomentQueue.displayDuration)
            guard !Task.isCancelled, let self else { return }
            self.show(self.momentQueue.advance())
        }
    }
}
