import Foundation
import HeadroomModel
import HeadroomSamples
import HeadroomStore
import HeadroomUI
import Testing

@Suite struct SampleDataModeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(sessions: [SessionInfo] = [], plan: PlanUsage = .empty) -> HeadroomSnapshot {
        HeadroomSnapshot(plan: plan, sessions: sessions, terminalBridgeConnected: false, issues: [], generatedAt: now)
    }

    private func session(_ id: String, _ activity: SessionActivity, since: Date) -> SessionInfo {
        SessionInfo(
            id: id, name: "Session \(id)", projectPath: nil, origin: .desktop, activity: activity,
            activitySince: since, startedAt: since, pid: nil, transcriptPath: nil, context: nil
        )
    }

    private var somePlan: PlanUsage {
        PlanUsage(weekly: LimitReading(
            kind: .weekly, usedPercent: 40, resetsAt: nil, resetIsEstimated: false, observedAt: now, source: .desktopApp
        ))
    }

    private let nothingReadable = AccessState(claudeDirectoryReadable: false, desktopDirectoryReadable: false, desktopAppInstalled: false)

    // MARK: Switching

    @Test func theSavedSettingPicksThePollSource() {
        #expect(SampleDataMode(isOn: false).pollSource == .realFiles)
        #expect(SampleDataMode(isOn: true).pollSource == .checkRealStateThenSample)
    }

    /// Launched with sample data on: nothing real has been read yet, so Settings' folder and
    /// terminal rows ("Checking…") and the panel's Connect / Disconnect terminal item would never
    /// learn the real state. The first tick checks once; later ticks read no files.
    @Test func sampleDataFromLaunchChecksTheRealStateOnce() {
        var mode = SampleDataMode(isOn: true)
        #expect(mode.pollSource == .checkRealStateThenSample)
        mode.recordRealCheck()
        #expect(mode.hasCheckedRealState)
        #expect(mode.pollSource == .sample)
        // The check's snapshot itself is never shown.
        #expect(!mode.showsRealSnapshot(fromPollStartedIn: mode.epoch))
    }

    @Test func aFailedOrDroppedCheckIsRetriedOnTheNextTick() {
        // recordRealCheck() only follows a check that was applied; until then every tick asks again.
        let mode = SampleDataMode(isOn: true)
        #expect(mode.pollSource == .checkRealStateThenSample)
        #expect(mode.pollSource == .checkRealStateThenSample)
    }

    @Test func turningOnAfterRealPollsReadsNoFiles() {
        var mode = SampleDataMode(isOn: false)
        mode.recordRealCheck()
        _ = mode.set(true)
        #expect(mode.pollSource == .sample)
        _ = mode.set(false)
        _ = mode.set(true)
        #expect(mode.pollSource == .sample, "the real state stays known across switches")
    }

    @Test func turningOnStopsReadingRealFilesAndClearsMoments() throws {
        var mode = SampleDataMode(isOn: false)
        mode.recordRealCheck()
        let switched = mode.set(true)
        let change = try #require(switched)
        #expect(mode.isOn)
        #expect(mode.pollSource == .sample)
        #expect(change == SampleDataMode.Switch(clearMoments: true, resetMomentBaseline: true, pollNow: true))
    }

    @Test func turningOffReadsRealFilesAgainFromAFreshBaseline() throws {
        var mode = SampleDataMode(isOn: true)
        let switched = mode.set(false)
        let change = try #require(switched)
        #expect(!mode.isOn)
        #expect(mode.pollSource == .realFiles)
        #expect(change.resetMomentBaseline)
        #expect(change.pollNow)
    }

    @Test func settingTheSameValueChangesNothing() {
        var mode = SampleDataMode(isOn: false)
        #expect(mode.set(false) == nil)
        #expect(mode.epoch == 0)
        _ = mode.set(true)
        #expect(mode.set(true) == nil)
        #expect(mode.epoch == 1)
    }

    @Test func momentsShowOnlyForRealDataAndWhenWanted() {
        #expect(SampleDataMode(isOn: false).showsMoments(userSetting: true))
        #expect(!SampleDataMode(isOn: false).showsMoments(userSetting: false))
        #expect(!SampleDataMode(isOn: true).showsMoments(userSetting: true))
        #expect(!SampleDataMode(isOn: true).showsMoments(userSetting: false))
    }

    // MARK: Polls that straddle a switch

    @Test func aRealPollFinishingAfterSampleDataWentOnIsNotShown() {
        var mode = SampleDataMode(isOn: false)
        let started = mode.epoch
        _ = mode.set(true)
        #expect(!mode.showsRealSnapshot(fromPollStartedIn: started))
    }

    @Test func aRealPollThatStartedBeforeAnOnOffRoundTripIsNotShown() {
        var mode = SampleDataMode(isOn: false)
        let started = mode.epoch
        _ = mode.set(true)
        _ = mode.set(false)
        #expect(!mode.showsRealSnapshot(fromPollStartedIn: started))
        #expect(mode.showsRealSnapshot(fromPollStartedIn: mode.epoch))
    }

    @Test func realPollsAreShownWhileSampleDataIsOff() {
        let mode = SampleDataMode(isOn: false)
        #expect(mode.showsRealSnapshot(fromPollStartedIn: mode.epoch))
    }

    @Test func explicitRealRefreshesDuringSampleDataAreNotShown() {
        // A grant or a Connect still reads the real folders for Settings, but the pill and panel
        // keep the sample snapshot.
        let mode = SampleDataMode(isOn: true)
        #expect(!mode.showsRealSnapshot(fromPollStartedIn: mode.epoch))
    }

    /// The contract `resetMomentBaseline` relies on: with no previous snapshot the first real poll
    /// announces nothing, however much changed while sample data showed.
    @Test func afterSampleDataTheFirstRealPollAnnouncesNothing() {
        let before = snapshot(sessions: [session("a", .working, since: now.addingTimeInterval(-3600))])
        let after = snapshot(sessions: [session("a", .idle, since: now)])
        #expect(!MomentDetector.moments(previous: before, current: after).isEmpty, "a diff would announce it")
        #expect(MomentDetector.moments(previous: nil, current: after).isEmpty)
    }

    // MARK: The panel

    @Test func thePanelOffersSampleDataOnlyWithoutAnyClaudeData() {
        let mode = SampleDataMode(isOn: false)
        #expect(mode.panelState(lastReal: snapshot(), access: nothingReadable) == .offered)
        #expect(mode.panelState(lastReal: snapshot(sessions: [session("a", .idle, since: now)]), access: nothingReadable) == .hidden)
        #expect(mode.panelState(lastReal: snapshot(plan: somePlan), access: nothingReadable) == .hidden)
        let claudeFolder = AccessState(claudeDirectoryReadable: true, desktopDirectoryReadable: false, desktopAppInstalled: false)
        #expect(mode.panelState(lastReal: snapshot(), access: claudeFolder) == .hidden)
        let desktopFolder = AccessState(claudeDirectoryReadable: false, desktopDirectoryReadable: true)
        #expect(mode.panelState(lastReal: snapshot(), access: desktopFolder) == .hidden)
    }

    @Test func noOfferBeforeTheFirstPoll() {
        #expect(SampleDataMode(isOn: false).panelState(lastReal: nil, access: nothingReadable) == .hidden)
    }

    @Test func thePanelSaysWhenSampleDataShows() {
        let mode = SampleDataMode(isOn: true)
        #expect(mode.panelState(lastReal: nil, access: nothingReadable) == .showing)
        #expect(mode.panelState(lastReal: snapshot(plan: somePlan), access: .full) == .showing)
    }

    @Test func switchingRedrawsThePanel() {
        let showcase = SampleData(now: now).showcase(terminalConnected: false)
        let empty = snapshot()
        #expect(PanelDrawKey(snapshot: empty, now: now, sampleData: .hidden) != PanelDrawKey(snapshot: empty, now: now, sampleData: .offered))
        #expect(PanelDrawKey(snapshot: showcase, now: now, sampleData: .hidden) != PanelDrawKey(snapshot: showcase, now: now, sampleData: .showing))
    }

    @Test func theSampleSnapshotReadsAsSampleDataInThePanel() {
        let showcase = SampleData(now: now).showcase(terminalConnected: true)
        let panel = PanelModel(snapshot: showcase, now: now, sampleData: .showing)
        #expect(panel.footer == "Sample data")
        #expect(panel.sampleDataTurnOff == "Turn off")
        #expect(panel.terminalMenuTitle == "Disconnect terminal")
        #expect(!panel.sections.isEmpty)
    }

    // MARK: VoiceOver and Settings

    @Test func voiceOverSaysItIsSampleData() {
        let showcase = SampleData(now: now).showcase(terminalConnected: false)
        let label = AccessibilitySummary.label(for: showcase, moment: nil, now: now, sampleData: true)
        #expect(label.hasPrefix("Headroom. Showing sample data. "))
        #expect(!AccessibilitySummary.label(for: showcase, moment: nil, now: now).contains("sample data"))
    }

    @Test func settingsExplainsTheToggle() {
        #expect(SettingsCopy.sampleDataDetail.contains("made-up"))
        #expect(!SettingsCopy.sampleDataDetail.localizedCaseInsensitiveContains("claude"))
    }
}
