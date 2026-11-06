import Foundation
import HeadroomModel
import Testing
@testable import HeadroomSamples

@Suite struct SampleDataTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Manila")!
        return calendar
    }

    @Test func weeklyResetIsTheNextSundayAtSeven() throws {
        // Thursday 2026-09-24 14:10 in Manila.
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 14, minute: 10)))
        let samples = SampleData(now: now, calendar: calendar)
        let reset = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: samples.weeklyReset)
        #expect(reset.day == 27 && reset.hour == 19 && reset.minute == 0 && reset.weekday == 1)
        #expect(samples.fiveHourReset == now.addingTimeInterval(2 * 3600 + 50 * 60))
    }

    @Test func resetsAreAlwaysAhead() {
        // Every hour of a week: the sample limits never read "reset passed".
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        for hour in 0..<(7 * 24) {
            let now = start.addingTimeInterval(Double(hour) * 3600)
            let samples = SampleData(now: now, calendar: calendar)
            #expect(samples.weeklyReset > now)
            #expect(samples.weeklyReset.timeIntervalSince(now) <= 7 * 86_400)
        }
    }

    @Test func showcaseHasEveryStateAndIsSortedForDisplay() {
        let samples = SampleData(now: Date(), calendar: calendar)
        let snapshot = samples.showcase(terminalConnected: false)
        #expect(snapshot.sessions == snapshot.sessions.sortedForDisplay())
        #expect(Set(snapshot.sessions.map(\.activity)) == [.working, .waitingForInput, .idle])
        #expect(snapshot.sessions.contains { $0.origin == .terminal })
        #expect(snapshot.sessions.filter { $0.activity == .idle }.count > 3, "idle rows collapse behind Show N more")
        #expect(snapshot.issues.isEmpty)
        #expect(snapshot.generatedAt == samples.now)
        // Past the 75 % warning, so the pill shows its number; below the 90 % moment.
        let weekly = snapshot.plan.weekly?.usedPercent ?? 0
        #expect(weekly >= 75 && weekly < 90)
        #expect(snapshot.plan.weekly?.isStale(now: samples.now) == false)
    }

    @Test func showcaseFollowsTheRealTerminalConnection() {
        let samples = SampleData.fixed
        #expect(samples.showcase(terminalConnected: true).terminalBridgeConnected)
        #expect(!samples.showcase(terminalConnected: false).terminalBridgeConnected)
    }

    @Test func showcaseIsRelativeToNow() {
        let early = SampleData(now: Date(timeIntervalSince1970: 1_800_000_000), calendar: calendar).showcase(terminalConnected: false)
        let late = SampleData(now: Date(timeIntervalSince1970: 1_800_086_400), calendar: calendar).showcase(terminalConnected: false)
        #expect(late.plan.weekly?.observedAt.timeIntervalSince(early.plan.weekly?.observedAt ?? .distantPast) == 86_400)
    }

    /// Nothing from a real Mac: invented folders under /Users/me, no transcripts, no processes.
    @Test func samplesAreSynthetic() {
        let samples = SampleData.fixed
        let all = samples.working + [samples.waitingTerminal, samples.longName] + samples.idle + samples.crowdedRows
            + samples.assumedWindows + samples.showcase(terminalConnected: true).sessions + samples.multiTool.sessions
            + [samples.codexTerminalSession]
        for session in all {
            if let path = session.projectPath {
                #expect(path.hasPrefix("/Users/me/"), "\(path)")
            }
            #expect(session.transcriptPath == nil)
            #expect(session.pid == nil)
        }
    }

    // MARK: Codex and Copilot (1.1 §6.5)

    @Test func showcaseShowsEveryTool() throws {
        let samples = SampleData(now: Date(timeIntervalSince1970: 1_790_230_000), calendar: calendar)
        let snapshot = samples.showcase(terminalConnected: false)
        #expect(snapshot.trackedTools == [.claude, .codex, .copilot])

        let codex = try #require(snapshot.codex)
        #expect(codex.planName == "Plus")
        #expect(!codex.hasFiveHourWindow, "Codex reports a weekly limit only")
        #expect(codex.limits.map(\.window) == [.weekly])
        #expect(codex.limits.map(\.usedPercent) == [94])
        let reset = calendar.dateComponents([.weekday, .hour, .minute], from: try #require(codex.limits[0].resetsAt))
        #expect(reset.weekday == 4 && reset.hour == 9 && reset.minute == 0, "resets Wed 9 AM")

        let copilot = try #require(snapshot.copilot)
        #expect(copilot.planName == "Pro")
        #expect(copilot.limits.first?.used == 512)
        #expect(copilot.limits.first?.allowance == 1500)
        #expect(copilot.limits.first?.unit == .aiCredits)

        let website = try #require(snapshot.sessions.first { $0.tool == .codex })
        #expect(website.name == "website")
        #expect(website.activity == .working)
        #expect(website.id.hasPrefix("codex:"))
        #expect(website.context.map { Int($0.percent.rounded()) } == 41)
        #expect(snapshot.sessions == snapshot.sessions.sortedForDisplay())
    }

    @Test func claudeOnlyShowcaseIsOnePointOhs() {
        let samples = SampleData.fixed
        let claude = samples.claudeOnlyShowcase(terminalConnected: true)
        #expect(claude.isClaudeOnly)
        #expect(claude.plan == samples.plan(weekly: 81, fiveHour: 34))
        #expect(claude.sessions == (samples.working + [samples.waitingTerminal] + Array(samples.idle.prefix(5))).sortedForDisplay())
        var multi = samples.showcase(terminalConnected: true)
        multi.sessions.removeAll { $0.tool != .claude }
        multi.codex = nil
        multi.copilot = nil
        #expect(multi == claude, "the showcase is 1.0's plus the other tools")
    }

    @Test func copilotResetsOnTheFirstAtMidnightUTC() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let now = try #require(utc.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 23, minute: 30)))
        let reset = SampleData(now: now, calendar: calendar).copilotReset
        #expect(utc.dateComponents([.year, .month, .day, .hour, .minute], from: reset) == DateComponents(year: 2026, month: 10, day: 1, hour: 0, minute: 0))
    }

    @Test func copilotStatesWithoutAReadingHaveNoLimits() {
        let samples = SampleData.fixed
        for status in [ToolStatus.notConnected, .signInExpired, .noIndividualUsage] {
            #expect(samples.copilot(status: status).limits.isEmpty)
        }
        #expect(samples.copilot(status: .offline).limits.count == 1)
        #expect(samples.copilot(allowance: nil).limits.first?.usedPercent == nil)
        #expect(samples.copilot(status: .notConnected).account == nil)
    }

    @Test func fixedDateIsThursdayAfternoon() {
        let components = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day, .hour, .minute], from: SampleData.fixed.now)
        #expect(components == DateComponents(year: 2026, month: 9, day: 24, hour: 14, minute: 10))
    }
}
