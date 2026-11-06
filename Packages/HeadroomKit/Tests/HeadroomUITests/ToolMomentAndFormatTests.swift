import Foundation
import HeadroomModel
import Testing
@testable import HeadroomUI

/// Moment copy (1.1 §6.2) and tool-limit text (1.1 §6.3).
@Suite struct ToolMomentAndFormatTests {
    let now = Fixture.now
    let format = Fixture.usFormat

    // MARK: Moments

    private func text(_ moment: Moment, _ tools: [ToolID]) -> String {
        MomentDisplay(moment, trackedTools: tools).text
    }

    @Test func limitMomentsNameTheirToolOnlyWithTwoOrMoreTools() {
        #expect(text(.toolLimitCrossed(tool: .codex, window: .weekly, percent: 90), [.codex]) == "Weekly at 90%")
        #expect(text(.toolLimitCrossed(tool: .codex, window: .weekly, percent: 100), [.codex]) == "Weekly limit reached")
        #expect(text(.toolLimitCrossed(tool: .codex, window: .weekly, percent: 90), [.claude, .codex]) == "Codex weekly at 90%")
        #expect(text(.toolLimitCrossed(tool: .codex, window: .weekly, percent: 100), [.claude, .codex]) == "Codex weekly limit reached")
        #expect(text(.limitCrossed(kind: .fiveHour, percent: 90), [.claude, .codex]) == "Claude 5-hour at 90%")
        #expect(text(.limitCrossed(kind: .weekly, percent: 100), [.claude, .copilot]) == "Claude weekly limit reached")
    }

    @Test func claudeLimitMomentsKeepTheOnePointOhText() {
        #expect(text(.limitCrossed(kind: .weekly, percent: 90), [.claude]) == "Weekly at 90%")
        #expect(MomentDisplay(.limitCrossed(kind: .fiveHour, percent: 100)).text == "5-hour limit reached")
        #expect(MomentDisplay(.limitCrossed(kind: .weekly, percent: 90)) == MomentDisplay(.limitCrossed(kind: .weekly, percent: 90), trackedTools: [.claude]))
    }

    @Test func copilotAtAHundredIsUsedUp() {
        #expect(text(.toolLimitCrossed(tool: .copilot, window: .monthly, percent: 90), [.copilot]) == "Monthly at 90%")
        #expect(text(.toolLimitCrossed(tool: .copilot, window: .monthly, percent: 100), [.copilot]) == "Monthly credits used up")
        #expect(text(.toolLimitCrossed(tool: .copilot, window: .monthly, percent: 90), [.claude, .copilot]) == "Copilot monthly at 90%")
        #expect(text(.toolLimitCrossed(tool: .copilot, window: .monthly, percent: 100), [.claude, .copilot]) == "Copilot credits used up")
        let full = MomentDisplay(.toolLimitCrossed(tool: .copilot, window: .monthly, percent: 100), trackedTools: [.copilot])
        #expect(full.tone == .limit(.critical))
        #expect(full.symbol == "gauge.with.needle")
    }

    @Test func sessionMomentsNeverNameTheToolOnScreen() {
        let moment = Moment.sessionNeedsInput(sessionID: "copilot:x", name: "harbor")
        let display = MomentDisplay(moment, trackedTools: [.claude, .copilot])
        #expect(display.text == "harbor needs you")
        #expect(display.spokenText == "Copilot session harbor needs you")
        #expect(MomentDisplay(moment, trackedTools: [.copilot]).spokenText == "Copilot session harbor needs you")
        #expect(MomentDisplay(.sessionFinished(sessionID: "a", name: "ledger"), trackedTools: [.claude]).spokenText == "ledger finished")
    }

    // MARK: Resets

    @Test func resetTextFollowsTheWindow() {
        #expect(format.reset(of: Fixture.limit(.weekly, 94, resetsAt: Fixture.codexWeeklyReset), now: now) == "resets Wed 9 AM")
        #expect(format.reset(of: Fixture.limit(.fiveHour, 20, resetsAt: now.addingTimeInterval(70 * 60)), now: now) == "resets in 1h 10m")
        #expect(format.reset(of: Fixture.limit(.monthly, 34, resetsAt: Fixture.copilotReset), now: now) == "resets Oct 1")
        #expect(format.reset(of: Fixture.limit(.minutes(180), 5, resetsAt: now.addingTimeInterval(3600)), now: now) == "resets in 1h")
    }

    @Test func resetTextWithoutAResetAhead() {
        #expect(format.reset(of: Fixture.limit(.weekly, 0, resetSinceReading: true), now: now) == "reset since last reading")
        #expect(format.reset(of: Fixture.limit(.fiveHour, 0), now: now) == "not started")
        #expect(format.reset(of: Fixture.limit(.fiveHour, 12), now: now) == "reset unknown")
        #expect(format.reset(of: Fixture.limit(.weekly, 12, resetsAt: now.addingTimeInterval(-60)), now: now) == "reset unknown")
    }

    @Test func spokenResetsUseWords() {
        #expect(format.spokenReset(of: Fixture.limit(.weekly, 94, resetsAt: Fixture.codexWeeklyReset), now: now) == "resets Wednesday 9 AM")
        #expect(format.spokenReset(of: Fixture.limit(.monthly, 34, resetsAt: Fixture.copilotReset), now: now) == "resets October 1")
        #expect(format.spokenReset(of: Fixture.limit(.fiveHour, 20, resetsAt: now.addingTimeInterval(70 * 60)), now: now)
            == "resets in 1 hour 10 minutes")
    }

    @Test func amountsAreWholeAndGrouped() {
        #expect(format.amount(512) == "512")
        #expect(format.amount(1500) == "1,500")
        #expect(format.amount(412.5) == "413")
        #expect(format.amount(.nan) == "–")
    }

    // MARK: Context with a baseline

    @Test func codexContextBarFollowsItsOwnPercent() throws {
        // 113k of 258.4k with a 12k baseline is 41 % by Codex's formula; the bar matches the number.
        let context = ContextUsage(
            usedTokens: 113_000, windowTokens: 258_400, model: "gpt-6-astra", windowIsExact: true, observedAt: nil,
            baselineTokens: 12_000
        )
        let badge = try #require(ContextBadge(context, format: format))
        #expect(badge.text == "41%")
        #expect(abs(badge.fraction - context.percent / 100) < 1e-9)
    }
}
