import Foundation
import HeadroomModel
import Testing
@testable import CopilotKit

/// Allowance math, plan changes and what a failed poll shows (1.1 §4.4–§4.6).
@Suite struct CopilotUsageMappingTests {
    private let now = midSeptember

    private func reading(used: Double = 512, unit: UsageUnit = .aiCredits, plan: CopilotPlan = .pro) -> ToolUsage {
        CopilotUsageMapping.applying(
            plan: plan, customAllowance: nil,
            to: ToolUsage(
                tool: .copilot,
                limits: [ToolLimit(
                    window: .monthly, usedPercent: nil, used: used, unit: unit, resetsAt: utc(2026, 10, 1),
                    observedAt: now
                )],
                status: .ok, account: "octocat"
            )
        )
    }

    @Test(arguments: [
        ("ai-credits", "ai-credits"), ("ai_credits", "ai-credits"), ("AI_Credits", "ai-credits"),
        ("AI Credits", "ai-credits"), (" requests ", "requests"), ("Requests", "requests"),
    ])
    func unitTypeSpellings(raw: String, normalized: String) {
        #expect(CopilotUsageMapping.normalizedUnitType(raw) == normalized)
    }

    @Test func allowanceMath() throws {
        let pro = try #require(reading(plan: .pro).limits.first)
        #expect(pro.allowance == 1_500)
        #expect(try #require(pro.usedPercent) == 512.0 * 100 / 1_500)
        #expect(reading(plan: .proPlus).limits.first?.allowance == 7_000)
        #expect(reading(plan: .max).limits.first?.usedPercent == 2.56)
        #expect(reading(unit: .premiumRequests, plan: .legacyProPlus).limits.first?.allowance == 1_500)
        // Not sure: usage only.
        let notSure = try #require(reading(plan: .notSure).limits.first)
        #expect(notSure.allowance == nil)
        #expect(notSure.usedPercent == nil)
        #expect(notSure.used == 512)
    }

    /// An organization seat's reading has GitHub's allowance: no Plan choice changes it, and a failed poll keeps it.
    @Test func anOrganizationSeatKeepsItsOwnAllowance() {
        let seat = ToolUsage(
            tool: .copilot,
            limits: [ToolLimit(
                window: .monthly, usedPercent: 1.64, used: 820, allowance: 50_000, unit: .aiCredits,
                resetsAt: utc(2026, 10, 1), observedAt: now
            )],
            status: .ok, planName: "Enterprise", account: "octocat", organizationSeat: true
        )
        #expect(CopilotUsageMapping.applying(plan: .pro, customAllowance: nil, to: seat) == seat)
        #expect(CopilotUsageMapping.applying(plan: .notSure, customAllowance: nil, to: seat) == seat)
        let offline = CopilotUsageMapping.afterFailure(
            UsageClientError.offline, last: seat, login: "octocat", plan: .pro, customAllowance: nil
        )
        #expect(offline.status == .offline)
        #expect(offline.limits == seat.limits)
        #expect(offline.planName == "Enterprise")
        #expect(offline.organizationSeat == true)
    }

    @Test func aNewPlanChoiceAppliesWithoutAFetch() {
        let usage = reading(plan: .notSure)
        let pro = CopilotUsageMapping.applying(plan: .pro, customAllowance: nil, to: usage)
        #expect(pro.planName == "Pro")
        #expect(pro.limits.first?.usedPercent == 512.0 * 100 / 1_500)
        let custom = CopilotUsageMapping.applying(plan: .custom, customAllowance: 1_024, to: pro)
        #expect(custom.planName == nil)
        #expect(custom.limits.first?.usedPercent == 50)
        let back = CopilotUsageMapping.applying(plan: .notSure, customAllowance: nil, to: custom)
        #expect(back.limits.first?.usedPercent == nil)
        #expect(back.limits.first?.allowance == nil)
    }

    @Test func otherToolsAreLeftAlone() {
        let codex = ToolUsage(
            tool: .codex, limits: [ToolLimit(window: .weekly, usedPercent: 40, resetsAt: nil, observedAt: now)],
            status: .ok
        )
        #expect(CopilotUsageMapping.applying(plan: .pro, customAllowance: nil, to: codex) == codex)
    }

    @Test func statuses() {
        #expect(CopilotUsageMapping.status(for: TokenRefreshError.notSignedIn) == .notConnected)
        #expect(CopilotUsageMapping.status(for: TokenRefreshError.rejected) == .signInExpired)
        #expect(CopilotUsageMapping.status(for: TokenRefreshError.offline) == .offline)
        #expect(CopilotUsageMapping.status(for: TokenRefreshError.rateLimited(retryAfter: nil)) == .rateLimited)
        #expect(CopilotUsageMapping.status(for: UsageClientError.unauthorized) == .signInExpired)
        #expect(CopilotUsageMapping.status(for: UsageClientError.rateLimited(retryAfter: 60)) == .rateLimited)
        #expect(CopilotUsageMapping.status(for: UsageClientError.offline) == .offline)
        // GitHub answered, just not with usage: not "Can't reach GitHub".
        #expect(CopilotUsageMapping.status(for: UsageClientError.unexpectedResponse(statusCode: 404)) == .unrecognized)
        #expect(CopilotUsageMapping.status(for: UsageClientError.unexpectedResponse(statusCode: 422)) == .unrecognized)
        #expect(CopilotUsageMapping.status(for: UsageClientError.unexpectedResponse(statusCode: 200)) == .unrecognized)
        #expect(CopilotUsageMapping.status(for: UsageClientError.unexpectedResponse(statusCode: 502)) == .offline)
        #expect(CopilotUsageMapping.status(for: URLError(.timedOut)) == .offline)
    }

    /// Offline and rate-limited keep the last reading (dimmed by its age); the others show none (§4.6).
    @Test func aFailedPollKeepsTheLastReadingOnlyWhenOfflineOrRateLimited() throws {
        let last = reading()
        for error: any Error in [UsageClientError.offline, UsageClientError.rateLimited(retryAfter: 60),
                                 TokenRefreshError.offline, UsageClientError.unexpectedResponse(statusCode: 502)]
        {
            let shown = CopilotUsageMapping.afterFailure(
                error, last: last, login: "octocat", plan: .pro, customAllowance: nil
            )
            #expect(shown.limits == last.limits)
            #expect(shown.status == CopilotUsageMapping.status(for: error))
            #expect(shown.account == "octocat")
            #expect(shown.isStale(now: now.addingTimeInterval(2 * 3600)))
        }
        for error: any Error in [
            TokenRefreshError.rejected, TokenRefreshError.notSignedIn, UsageClientError.unexpectedResponse(statusCode: 404),
        ] {
            let shown = CopilotUsageMapping.afterFailure(
                error, last: last, login: "octocat", plan: .pro, customAllowance: nil
            )
            #expect(shown.limits.isEmpty)
        }
        #expect(CopilotUsageMapping.afterFailure(
            TokenRefreshError.rejected, last: last, login: nil, plan: .pro, customAllowance: nil
        ).status == .signInExpired)
    }

    @Test func aFailedPollWithoutAReading() {
        let shown = CopilotUsageMapping.afterFailure(
            UsageClientError.offline, last: nil, login: "octocat", plan: .max, customAllowance: nil
        )
        #expect(shown == ToolUsage(tool: .copilot, status: .offline, planName: "Max", account: "octocat"))
    }

    /// The kept reading follows a plan change made while offline.
    @Test func theKeptReadingFollowsThePlan() {
        let shown = CopilotUsageMapping.afterFailure(
            UsageClientError.offline, last: reading(plan: .pro), login: "octocat", plan: .notSure, customAllowance: nil
        )
        #expect(shown.limits.first?.usedPercent == nil)
        #expect(shown.limits.first?.used == 512)
    }

    /// Past the 1st, the kept reading rolls over with `ToolLimit.rolledOver` (HeadroomModel) to 0 and the next month.
    @Test func aKeptReadingRollsOverAtTheUTCMonth() {
        let rolled = reading().rolledOver(now: utc(2026, 10, 1, 0, 1))
        #expect(rolled.limits.first?.used == 0)
        #expect(rolled.limits.first?.usedPercent == 0)
        #expect(rolled.limits.first?.resetsAt == utc(2026, 11, 1))
    }
}

/// When to poll (1.1 §4.7).
@Suite struct CopilotPollPolicyTests {
    private let start = midSeptember

    private func minutes(_ count: Double) -> Date { start.addingTimeInterval(count * 60) }

    @Test func pollsRightAwayThenEveryFifteenMinutes() {
        var policy = CopilotPollPolicy()
        #expect(policy.shouldPoll(.timer, now: start))
        #expect(policy.nextTimerPoll(now: start) == start)
        policy.recordSuccess(at: start)
        #expect(policy.nextTimerPoll(now: start) == minutes(15))
        #expect(!policy.shouldPoll(.timer, now: minutes(14)))
        #expect(policy.shouldPoll(.timer, now: minutes(15)))
    }

    @Test func thePanelRefreshesReadingsOlderThanFiveMinutes() {
        var policy = CopilotPollPolicy()
        #expect(policy.shouldPoll(.panelOpened, now: start))
        policy.recordSuccess(at: start)
        #expect(!policy.shouldPoll(.panelOpened, now: minutes(5)))
        #expect(policy.shouldPoll(.panelOpened, now: minutes(5.1)))
    }

    @Test func wakeRefreshAndSignInPoll() {
        var policy = CopilotPollPolicy()
        policy.recordSuccess(at: start)
        #expect(policy.shouldPoll(.wake, now: minutes(1)))
        #expect(policy.shouldPoll(.manual, now: minutes(1)))
        #expect(policy.shouldPoll(.signedIn, now: minutes(1)))
    }

    @Test func backoffDoubles() {
        #expect((0...8).map { CopilotPollPolicy.backoff(afterFailures: $0) / 60 } == [0, 1, 2, 4, 8, 16, 32, 60, 60])
        #expect(CopilotPollPolicy.backoff(afterFailures: 1_000) == 3_600)
    }

    @Test func errorsBackOff() {
        var policy = CopilotPollPolicy()
        policy.recordSuccess(at: start)
        policy.recordFailure(UsageClientError.offline, at: minutes(15))
        #expect(policy.nextTimerPoll(now: minutes(15)) == minutes(16))
        for trigger: CopilotPollPolicy.Trigger in [.timer, .panelOpened, .wake, .manual] {
            #expect(!policy.shouldPoll(trigger, now: minutes(15.5)))
        }
        // A new sign-in doesn't wait for the backoff.
        #expect(policy.shouldPoll(.signedIn, now: minutes(15.5)))
        #expect(policy.shouldPoll(.timer, now: minutes(16)))
        policy.recordFailure(UsageClientError.offline, at: minutes(16))
        #expect(policy.nextTimerPoll(now: minutes(16)) == minutes(18))
        policy.recordFailure(UsageClientError.offline, at: minutes(18))
        #expect(policy.nextTimerPoll(now: minutes(18)) == minutes(22))
        #expect(policy.consecutiveFailures == 3)
        // Success resets it: back to every 15 minutes.
        policy.recordSuccess(at: minutes(22))
        #expect(policy.consecutiveFailures == 0)
        #expect(policy.blockedUntil == nil)
        #expect(policy.nextTimerPoll(now: minutes(22)) == minutes(37))
    }

    @Test func rateLimitsWaitForRetryAfter() {
        var policy = CopilotPollPolicy()
        policy.recordFailure(UsageClientError.rateLimited(retryAfter: 600), at: start)
        #expect(policy.nextTimerPoll(now: start) == minutes(10))
        #expect(!policy.shouldPoll(.panelOpened, now: minutes(9)))
        #expect(policy.shouldPoll(.timer, now: minutes(10)))
        // A shorter Retry-After than the backoff: the backoff wins.
        policy.recordFailure(TokenRefreshError.rateLimited(retryAfter: 5), at: minutes(10))
        #expect(policy.nextTimerPoll(now: minutes(10)) == minutes(12))
    }

    @Test func theHourlyBudgetHoldsPollsBack() {
        var policy = CopilotPollPolicy()
        for poll in 0..<6 { policy.recordSuccess(at: minutes(Double(poll) * 5.5)) }
        // 6 polls × 3 requests = 18: nothing more this hour, not even after sign-in.
        #expect(!policy.shouldPoll(.panelOpened, now: minutes(40)))
        #expect(!policy.shouldPoll(.signedIn, now: minutes(40)))
        #expect(!policy.shouldPoll(.timer, now: minutes(50)))
        // The first poll's requests age out an hour after it.
        #expect(policy.nextTimerPoll(now: minutes(40)) == minutes(60))
        #expect(policy.shouldPoll(.timer, now: minutes(60)))
    }

    @Test func otherRequestsCountToo() {
        var policy = CopilotPollPolicy()
        policy.recordRequests(1, at: start)
        for poll in 0..<5 { policy.recordSuccess(at: minutes(Double(poll) * 6)) }
        // 1 + 15 = 16: one more poll would pass 18.
        #expect(!policy.shouldPoll(.panelOpened, now: minutes(40)))
    }

    /// Three hours of a panel opened every 5 minutes on top of the timer, with a failure now and then: never more
    /// than 18 requests in any hour.
    @Test func neverMoreThanEighteenRequestsAnHour() {
        var policy = CopilotPollPolicy()
        var requests: [Date] = []
        var minute = 0.0
        var outcome = 0
        while minute < 180 {
            let now = minutes(minute)
            let trigger: CopilotPollPolicy.Trigger = minute.truncatingRemainder(dividingBy: 5) == 0 ? .panelOpened : .timer
            if policy.shouldPoll(trigger, now: now) {
                requests += Array(repeating: now, count: CopilotPollPolicy.requestsPerPoll)
                outcome += 1
                if outcome % 4 == 0 {
                    policy.recordFailure(UsageClientError.offline, at: now)
                } else {
                    policy.recordSuccess(at: now)
                }
            }
            minute += 0.5
        }
        for request in requests {
            let inHour = requests.filter { $0 >= request && $0.timeIntervalSince(request) < 3600 }
            #expect(inHour.count <= 18)
        }
        #expect(requests.count > 18)
    }

    @Test func resetStartsOver() {
        var policy = CopilotPollPolicy()
        policy.recordFailure(UsageClientError.offline, at: start)
        policy.reset()
        #expect(policy.shouldPoll(.timer, now: start))
        #expect(policy.lastSuccess == nil)
    }
}
