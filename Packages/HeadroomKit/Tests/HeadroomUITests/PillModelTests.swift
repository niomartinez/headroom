import Foundation
import HeadroomModel
import Testing
@testable import HeadroomUI

@Suite struct PillModelTests {
    let now = Fixture.now

    private func model(
        plan: PlanUsage = Fixture.plan(weekly: 40, fiveHour: 10),
        sessions: [SessionInfo] = [],
        moment: Moment? = nil
    ) -> PillModel {
        PillModel(snapshot: Fixture.snapshot(plan: plan, sessions: sessions), moment: moment, now: now)
    }

    // MARK: Dot

    @Test func dotIsIdleWithoutSessions() {
        #expect(model().dot == .idle)
    }

    @Test func dotIsIdleWhenAllSessionsIdle() {
        #expect(model(sessions: [Fixture.session("a", .idle), Fixture.session("b", .idle)]).dot == .idle)
    }

    @Test func dotIsWorkingWhenAnySessionWorks() {
        #expect(model(sessions: [Fixture.session("a", .idle), Fixture.session("b", .working)]).dot == .working)
    }

    @Test func waitingWinsOverWorking() {
        let sessions = [Fixture.session("a", .working), Fixture.session("b", .waitingForInput), Fixture.session("c", .working)]
        #expect(model(sessions: sessions).dot == .waiting)
    }

    // MARK: Count

    @Test func countHiddenWhenNoActiveSessions() {
        #expect(model().count == nil)
        #expect(model(sessions: [Fixture.session("a", .idle)]).count == nil)
    }

    @Test func countIsWorkingPlusWaiting() {
        let sessions = [
            Fixture.session("a", .working), Fixture.session("b", .waitingForInput),
            Fixture.session("c", .idle), Fixture.session("d", .working),
        ]
        #expect(model(sessions: sessions).count == 3)
    }

    // MARK: Trailing number

    @Test func noNumberBelowSeventyFive() {
        #expect(model(plan: Fixture.plan(weekly: 74, fiveHour: 60)).badge == nil)
        #expect(model(plan: Fixture.plan(weekly: 74.4, fiveHour: nil)).badge == nil)
    }

    @Test func numberAtSeventyFiveIsWarning() {
        #expect(model(plan: Fixture.plan(weekly: 75, fiveHour: 10)).badge == PercentBadge(text: "75%", severity: .warning))
    }

    @Test func numberShowsTightestLimitOnly() {
        let badge = model(plan: Fixture.plan(weekly: 89, fiveHour: 14)).badge
        #expect(badge == PercentBadge(text: "89%", severity: .warning))
        let fiveHourTighter = model(plan: Fixture.plan(weekly: 80, fiveHour: 96)).badge
        #expect(fiveHourTighter == PercentBadge(text: "96%", severity: .critical))
    }

    @Test func numberIsCriticalAtNinetyFiveAndClampsAtHundred() {
        #expect(model(plan: Fixture.plan(weekly: 95, fiveHour: 0)).badge?.severity == .critical)
        #expect(model(plan: Fixture.plan(weekly: 130, fiveHour: 0)).badge == PercentBadge(text: "100%", severity: .critical))
    }

    @Test func severityFollowsTheDisplayedNumber() {
        // 94.6 is shown as "95%", so it must also be colored critical.
        #expect(model(plan: Fixture.plan(weekly: 94.6, fiveHour: nil)).badge == PercentBadge(text: "95%", severity: .critical))
    }

    @Test func garbagePercentShowsNothing() {
        let pill = model(plan: Fixture.plan(weekly: .nan, fiveHour: .infinity))
        #expect(pill.badge == nil)
        #expect(pill.gauge.outer == nil)
        #expect(pill.gauge.inner == nil)
    }

    // MARK: Gauge

    @Test func gaugeOuterIsWeeklyInnerIsFiveHour() {
        let gauge = model(plan: Fixture.plan(weekly: 89, fiveHour: 14)).gauge
        #expect(gauge.outer == GaugeModel.Ring(fraction: 0.89, severity: .warning))
        #expect(gauge.inner == GaugeModel.Ring(fraction: 0.14, severity: .normal))
    }

    @Test func gaugeClampsFractions() {
        let gauge = model(plan: Fixture.plan(weekly: 140, fiveHour: -8)).gauge
        #expect(gauge.outer?.fraction == 1)
        #expect(gauge.inner?.fraction == 0)
    }

    // MARK: Stale and no data

    @Test func freshDataIsNotStale() {
        let pill = model(plan: Fixture.plan(weekly: 89, fiveHour: 14, age: 30 * 60))
        #expect(!pill.isStale)
        #expect(!pill.gauge.isStale)
    }

    @Test func staleWhenNewestReadingOlderThanThirtyMinutes() {
        let pill = model(plan: Fixture.plan(weekly: 89, fiveHour: 14, age: 31 * 60))
        #expect(pill.isStale)
        #expect(pill.gauge.isStale)
        #expect(pill.badge?.text == "89%")
    }

    @Test func staleUsesTheNewestReading() {
        let plan = PlanUsage(
            fiveHour: Fixture.reading(.fiveHour, 14, age: 60),
            weekly: Fixture.reading(.weekly, 89, age: 3 * 3600)
        )
        #expect(!model(plan: plan).isStale)
    }

    @Test func noDataShowsTracksOnlyAndNoNumber() {
        let pill = model(plan: .empty, sessions: [Fixture.session("a", .working)])
        #expect(pill.hasNoData)
        #expect(pill.gauge.hasNoData)
        #expect(pill.badge == nil)
        #expect(!pill.isStale)
        #expect(pill.dot == .working)
        #expect(pill.count == 1)
    }

    @Test func partialDataIsNotNoData() {
        let pill = model(plan: Fixture.plan(weekly: nil, fiveHour: 20))
        #expect(!pill.hasNoData)
        #expect(pill.gauge.outer == nil)
        #expect(pill.gauge.inner?.fraction == 0.2)
    }

    // MARK: Moments

    @Test func noMomentByDefault() {
        #expect(model().moment == nil)
    }

    @Test func finishedMoment() {
        let pill = model(moment: .sessionFinished(sessionID: "s1", name: "Tidy build script"))
        #expect(pill.moment == MomentDisplay(symbol: "checkmark.circle.fill", name: "Tidy build script", status: "finished", tone: .finished))
        #expect(pill.moment?.text == "Tidy build script finished")
    }

    @Test func needsInputMoment() {
        let pill = model(moment: .sessionNeedsInput(sessionID: "s1", name: "Tidy build script"))
        #expect(pill.moment == MomentDisplay(symbol: "exclamationmark.circle.fill", name: "Tidy build script", status: "needs you", tone: .needsInput))
        #expect(pill.moment?.text == "Tidy build script needs you")
    }

    @Test func limitMoments() {
        let weekly90 = model(moment: .limitCrossed(kind: .weekly, percent: 90)).moment
        #expect(weekly90 == MomentDisplay(symbol: "gauge.with.needle", text: "Weekly at 90%", tone: .limit(.warning)))
        let fiveHour100 = model(moment: .limitCrossed(kind: .fiveHour, percent: 100)).moment
        #expect(fiveHour100 == MomentDisplay(symbol: "gauge.with.needle", text: "5-hour limit reached", tone: .limit(.critical)))
        #expect(model(moment: .limitCrossed(kind: .weekly, percent: 100)).moment?.text == "Weekly limit reached")
        #expect(model(moment: .limitCrossed(kind: .fiveHour, percent: 90)).moment?.text == "5-hour at 90%")
    }

    @Test func fullNamesArePreservedForMeasuredLayout() {
        let name = "Investigate the intermittent upload failure"
        let moment = model(moment: .sessionFinished(sessionID: "s1", name: name)).moment
        #expect(moment?.text == "\(name) finished")
        // Only the view truncates, according to actual text width; the status always shows.
        #expect(moment?.name == name)
        #expect(moment?.status == "finished")
    }

    @Test func onlySessionMomentsHaveAName() {
        let needs = model(moment: .sessionNeedsInput(sessionID: "s1", name: "harbor")).moment
        #expect(needs?.name == "harbor")
        #expect(needs?.status == "needs you")
        let limit = model(moment: .limitCrossed(kind: .weekly, percent: 90)).moment
        #expect(limit?.name == nil)
        #expect(limit?.status == "Weekly at 90%")
        // A display built from plain text is shown whole.
        let plain = MomentDisplay(symbol: "gauge.with.needle", text: "Weekly at 90%", tone: .limit(.warning))
        #expect(plain.name == nil)
        #expect(plain == limit)
    }

    @Test func blankNamesFallBack() {
        #expect(model(moment: .sessionNeedsInput(sessionID: "s1", name: "  \n")).moment?.text == "A session needs you")
    }

    // MARK: Accessibility

    @Test func accessibilityLabelSummarisesThePill() {
        let sessions = [Fixture.session("a", .working), Fixture.session("b", .waitingForInput)]
        let pill = model(plan: Fixture.plan(weekly: 89, fiveHour: 14), sessions: sessions)
        #expect(pill.accessibilityLabel == "2 active sessions, 1 needs input. Weekly 89%, 5-hour 14%.")
        #expect(model(plan: .empty).accessibilityLabel == "No active sessions. No usage data.")
        let stale = model(plan: Fixture.plan(weekly: 20, fiveHour: nil, age: 3600), sessions: [Fixture.session("a", .working)])
        #expect(stale.accessibilityLabel == "1 active session. Weekly 20%. Usage data is out of date.")
    }
}
