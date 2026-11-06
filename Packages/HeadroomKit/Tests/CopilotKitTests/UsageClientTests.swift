import Foundation
import HeadroomModel
import Testing
@testable import CopilotKit

/// The login and this month's usage (1.1 §4.3, §4.4, §4.6), HTTP stubbed with `URLProtocol`.
@Suite struct UsageClientTests {
    private let now = midSeptember
    private let token = "ghu_EXAMPLEaccess0001"

    private func client(_ http: HTTPStub) -> UsageClient {
        UsageClient(transport: http.transport, userAgent: http.userAgent)
    }

    private func usage(
        _ client: UsageClient, plan: CopilotPlan = .pro, custom: Double? = nil, now: Date? = nil
    ) async throws -> ToolUsage {
        try await client.usage(
            login: "octocat", accessToken: token, plan: plan, customAllowance: custom, now: now ?? self.now
        )
    }

    // MARK: Login

    @Test func currentLoginSendsTheAPIHeaders() async throws {
        let http = HTTPStub([.json(try fixture("user"))])
        #expect(try await client(http).currentLogin(accessToken: token, now: now) == "octocat")
        let request = try #require(http.requests.first)
        #expect(request.method == "GET")
        #expect(request.url.absoluteString == "https://api.github.com/user")
        #expect(request.header("Authorization") == "Bearer ghu_EXAMPLEaccess0001")
        #expect(request.header("Accept") == "application/vnd.github+json")
        #expect(request.header("X-GitHub-Api-Version") == "2026-03-10")
    }

    @Test(arguments: [#"{"id":1}"#, #"{"login":"../admin"}"#, #"{"login":""}"#, "<html>"])
    func anUnreadableLoginIsUnexpected(body: String) async throws {
        let http = HTTPStub([.json(body)])
        await #expect(throws: UsageClientError.unexpectedResponse(statusCode: 200)) {
            try await client(http).currentLogin(accessToken: token, now: now)
        }
    }

    // MARK: Usage

    @Test func decodesTheOpenAPIExample() async throws {
        let http = HTTPStub([.json(try fixture("usage_openapi_example"))])
        let usage = try await usage(client(http))
        #expect(usage == ToolUsage(
            tool: .copilot,
            limits: [ToolLimit(
                window: .monthly, usedPercent: 27.5, used: 412.5, allowance: 1_500, extra: nil, unit: .aiCredits,
                resetsAt: utc(2026, 10, 1), resetIsEstimated: false, observedAt: now
            )],
            hasFiveHourWindow: false,
            status: .ok,
            planName: "Pro",
            account: "octocat"
        ))
        #expect(usage.staleAfter == 45 * 60)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.url.absoluteString
            == "https://api.github.com/users/octocat/settings/billing/ai_credit/usage?year=2026&month=9")
        #expect(request.header("Authorization") == "Bearer ghu_EXAMPLEaccess0001")
        #expect(request.header("X-GitHub-Api-Version") == "2026-03-10")
    }

    /// `ai-credits`, `ai_credits`, `AI_Credits` and `AI Credits` all count; other units and items without a unit
    /// don't.
    @Test func sumsTheCreditItemsInEverySpelling() async throws {
        let http = HTTPStub([.json(try fixture("usage_credit_variants"))])
        let limit = try #require(try await usage(client(http), plan: .proPlus).limits.first)
        #expect(limit.used == 412)
        #expect(limit.allowance == 7_000)
        #expect(limit.extra == nil)
        #expect(http.requests.count == 1)
    }

    @Test func extraUsageIsTheBilledNetQuantity() async throws {
        let http = HTTPStub([.json(try fixture("usage_extra"))])
        let limit = try #require(try await usage(client(http)).limits.first)
        #expect(limit.used == 1_620)
        #expect(limit.extra == 120)
        #expect(limit.usedPercent == 108)
    }

    @Test func notSureShowsUsageWithoutAPercent() async throws {
        let http = HTTPStub([.json(try fixture("usage_openapi_example"))])
        let usage = try await usage(client(http), plan: .notSure)
        let limit = try #require(usage.limits.first)
        #expect(limit.used == 412.5)
        #expect(limit.allowance == nil)
        #expect(limit.usedPercent == nil)
        #expect(usage.planName == nil)
        #expect(usage.tightest == nil)
    }

    @Test func customAllowance() async throws {
        let http = HTTPStub([.json(try fixture("usage_openapi_example")), .json(try fixture("usage_openapi_example"))])
        let client = client(http)
        #expect(try await usage(client, plan: .custom, custom: 825).limits.first?.usedPercent == 50)
        // Out of range: no percent rather than a wrong one.
        #expect(try await usage(client, plan: .custom, custom: 0).limits.first?.usedPercent == nil)
    }

    @Test func legacyPlansAskOnlyForPremiumRequests() async throws {
        let http = HTTPStub([.json(try fixture("usage_premium_requests"))])
        let usage = try await usage(client(http), plan: .legacyPro)
        let limit = try #require(usage.limits.first)
        #expect(limit.unit == .premiumRequests)
        #expect(limit.used == 222)
        #expect(limit.allowance == 300)
        #expect(limit.usedPercent == 74)
        #expect(usage.planName == "Pro")
        #expect(http.requests.map(\.url.path) == ["/users/octocat/settings/billing/premium_request/usage"])
    }

    /// Credits first; with no credit items, premium requests at most once an hour (§4.4).
    @Test func detectsPremiumRequestsAtMostOnceAnHour() async throws {
        let empty = try fixture("usage_empty")
        let premium = try fixture("usage_premium_requests")
        let http = HTTPStub([.json(empty), .json(premium)])
        let client = client(http)

        let first = try await usage(client, plan: .notSure)
        #expect(first.status == .ok)
        #expect(first.limits.first?.unit == .premiumRequests)
        #expect(first.limits.first?.used == 222)
        #expect(http.requests.map(\.url.path) == [
            "/users/octocat/settings/billing/ai_credit/usage", "/users/octocat/settings/billing/premium_request/usage",
        ])

        // 15 minutes later: only the credits endpoint is asked; the premium check still stands, as of its time.
        http.enqueue(.json(empty))
        let second = try await usage(client, plan: .notSure, now: now.addingTimeInterval(15 * 60))
        #expect(second.limits.first?.used == 222)
        #expect(second.limits.first?.observedAt == now)
        #expect(http.requests.count == 3)

        // An hour after the check: asked again, and with no items anywhere the seat too.
        http.enqueue(.json(empty), .json(empty), .http(404, ""))
        let third = try await usage(client, plan: .notSure, now: now.addingTimeInterval(60 * 60))
        #expect(third.status == .noIndividualUsage)
        #expect(http.requests.count == 6)
    }

    /// Credits items win: premium requests aren't asked.
    @Test func creditItemsWin() async throws {
        let http = HTTPStub([.json(try fixture("usage_openapi_example"))])
        _ = try await usage(client(http), plan: .notSure)
        #expect(http.requests.count == 1)
    }

    /// G1's real answer for an organization-paid seat: 200 with no items on either endpoint. Here GitHub also
    /// refuses the seat's quota.
    @Test func noItemsAnywhereIsNoIndividualUsage() async throws {
        let empty = try fixture("usage_empty")
        let http = HTTPStub([.json(empty), .json(empty), .http(403, #"{"message":"Resource not accessible by integration"}"#)])
        let usage = try await usage(client(http))
        #expect(usage == ToolUsage(tool: .copilot, status: .noIndividualUsage, planName: "Pro", account: "octocat"))
    }

    // MARK: Organization seat (Nio, 2026-10-02)

    /// Nothing billed to the account: the organization-paid seat's quota, with GitHub's allowance whatever the Plan
    /// picker says.
    @Test func anOrganizationSeatShowsItsQuota() async throws {
        let empty = try fixture("usage_empty")
        let http = HTTPStub([.json(empty), .json(empty), .json(try fixture("copilot_user_enterprise"))])
        let usage = try await usage(client(http), plan: .pro)
        #expect(usage == ToolUsage(
            tool: .copilot,
            limits: [ToolLimit(
                window: .monthly, usedPercent: 1.64, used: 820, allowance: 50_000, unit: .aiCredits,
                resetsAt: utc(2026, 10, 1), observedAt: now
            )],
            status: .ok,
            planName: "Enterprise",
            account: "octocat",
            organizationSeat: true
        ))
        let request = try #require(http.requests.last)
        #expect(request.url.absoluteString == "https://api.github.com/copilot_internal/user")
        #expect(request.header("X-GitHub-Api-Version") == "2026-03-10")
    }

    @Test func aBusinessSeatOnPremiumRequests() async throws {
        let empty = try fixture("usage_empty")
        let seat = #"{"copilot_plan":"business","token_based_billing":false,"quota_snapshots":{"premium_interactions":{"entitlement":300,"remaining":75,"unlimited":false}}}"#
        let http = HTTPStub([.json(empty), .json(empty), .json(seat)])
        let usage = try await usage(client(http), plan: .notSure)
        let limit = try #require(usage.limits.first)
        #expect(limit.unit == .premiumRequests)
        #expect(limit.used == 225)
        #expect(limit.allowance == 300)
        #expect(limit.usedPercent == 75)
        #expect(usage.planName == "Business")
    }

    /// GitHub refusing the undocumented endpoint, or answering anything else, leaves the documented answer: never
    /// "Sign-in expired", never an error.
    @Test(arguments: [
        StubAnswer.http(401, ""), .http(403, ""), .http(404, ""), .http(500, ""), .networkError, .json("<html>"),
        .json(#"{"copilot_plan":"individual","quota_snapshots":{"premium_interactions":{"entitlement":300,"remaining":100,"unlimited":false}}}"#),
        .json(#"{"copilot_plan":"enterprise","quota_snapshots":{"premium_interactions":{"entitlement":0,"remaining":0,"unlimited":true}}}"#),
        .json(#"{"copilot_plan":"enterprise","quota_snapshots":{"chat":{"entitlement":0,"unlimited":true}}}"#),
    ])
    func noSeatQuotaKeepsNoIndividualUsage(answer: StubAnswer) async throws {
        let empty = try fixture("usage_empty")
        let http = HTTPStub([.json(empty), .json(empty), answer])
        let usage = try await usage(client(http))
        #expect(usage == ToolUsage(tool: .copilot, status: .noIndividualUsage, planName: "Pro", account: "octocat"))
        #expect(http.requests.count == 3)
    }

    /// Items only in a unit Headroom doesn't know: no number is guessed.
    @Test func unknownUnitsAreUnrecognized() async throws {
        let http = HTTPStub([.json(try fixture("usage_unknown_unit")), .json(try fixture("usage_empty"))])
        let usage = try await usage(client(http))
        #expect(usage.status == .unrecognized)
        #expect(usage.limits.isEmpty)
    }

    /// Pro counts credits, but the account has premium requests: the reading shows without a percent.
    @Test func aPresetInTheOtherUnitGivesNoPercent() async throws {
        let http = HTTPStub([.json(try fixture("usage_empty")), .json(try fixture("usage_premium_requests"))])
        let limit = try #require(try await usage(client(http), plan: .pro).limits.first)
        #expect(limit.unit == .premiumRequests)
        #expect(limit.allowance == nil)
        #expect(limit.usedPercent == nil)
    }

    // MARK: UTC month

    /// Sep 30 20:00 in UTC−7 is Oct 1 03:00 UTC: GitHub's October, resetting Nov 1 00:00 UTC, which is Oct 31 in
    /// UTC−7.
    @Test func asksForTheUTCMonth() async throws {
        let pacific = try #require(TimeZone(secondsFromGMT: -7 * 3600))
        var local = Calendar(identifier: .gregorian)
        local.timeZone = pacific
        let now = try #require(local.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 20)))
        let http = HTTPStub([.json(try fixture("usage_openapi_example"))])
        let limit = try #require(try await usage(client(http), now: now).limits.first)
        #expect(http.requests.first?.url.query == "year=2026&month=10")
        #expect(limit.resetsAt == utc(2026, 11, 1))
        #expect(local.dateComponents([.month, .day], from: try #require(limit.resetsAt)) == DateComponents(month: 10, day: 31))
    }

    /// Oct 1 07:00 in Manila (UTC+8) is still Sep 30 in UTC: September, resetting at 08:00 Manila time, "Oct 1".
    @Test func theResetIsTheNextFirstInUTC() async throws {
        let manila = try #require(TimeZone(secondsFromGMT: 8 * 3600))
        var local = Calendar(identifier: .gregorian)
        local.timeZone = manila
        let now = try #require(local.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 7)))
        let http = HTTPStub([.json(try fixture("usage_openapi_example"))])
        let limit = try #require(try await usage(client(http), now: now).limits.first)
        #expect(http.requests.first?.url.query == "year=2026&month=9")
        #expect(limit.resetsAt == utc(2026, 10, 1))
        #expect(local.dateComponents([.month, .day, .hour], from: try #require(limit.resetsAt))
            == DateComponents(month: 10, day: 1, hour: 8))
    }

    @Test func decemberResetsInJanuary() async throws {
        let http = HTTPStub([.json(try fixture("usage_openapi_example"))])
        let limit = try #require(try await usage(client(http), now: utc(2026, 12, 31, 23, 59)).limits.first)
        #expect(http.requests.first?.url.query == "year=2026&month=12")
        #expect(limit.resetsAt == utc(2027, 1, 1))
    }

    // MARK: Errors

    @Test(arguments: [
        (StubAnswer.http(401, #"{"message":"Bad credentials"}"#), UsageClientError.unauthorized),
        (.http(403, "", headers: ["Retry-After": "90"]), .rateLimited(retryAfter: 90)),
        (.http(429, "", headers: ["Retry-After": "Tue, 15 Sep 2026 12:05:00 GMT"]), .rateLimited(retryAfter: 300)),
        (.http(403, "", headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1789474200"]),
         .rateLimited(retryAfter: 600)),
        (.http(429, ""), .rateLimited(retryAfter: nil)),
        // A wait longer than a day isn't believed: a huge one would overflow the app's timer.
        (.http(429, "", headers: ["Retry-After": "1e22"]), .rateLimited(retryAfter: 86_400)),
        (.http(403, "", headers: ["x-ratelimit-reset": "99999999999999999"]), .rateLimited(retryAfter: 86_400)),
        (.http(500, ""), .offline),
        (.http(503, ""), .offline),
        (.networkError, .offline),
        (.http(404, #"{"message":"Not Found"}"#), .unexpectedResponse(statusCode: 404)),
        (.json(#"{"timePeriod":{"year":2026,"month":9}}"#), .unexpectedResponse(statusCode: 200)),
        (.json("<html>"), .unexpectedResponse(statusCode: 200)),
    ])
    func errors(answer: StubAnswer, expected: UsageClientError) async throws {
        let http = HTTPStub([answer])
        await #expect(throws: expected) { try await usage(client(http)) }
    }

    @Test func aLoginThatCantGoInAPathIsRefused() async throws {
        let http = HTTPStub()
        await #expect(throws: UsageClientError.unexpectedResponse(statusCode: 0)) {
            try await client(http).usage(
                login: "octo/cat", accessToken: token, plan: .pro, customAllowance: nil, now: now
            )
        }
        #expect(http.requests.isEmpty)
    }
}

/// `TokenRefresher` with the real `DeviceFlow` and `UsageClient` (1.1 §4.3): rotation saved before use, one retry
/// after a 401, a rejected refresh ends the sign-in.
@Suite struct SignedInRequestTests {
    private let now = midSeptember

    private let original = TokenPair(
        access: "ghu_EXAMPLEaccess0001", refresh: "ghr_EXAMPLErefresh0001",
        accessExpiresAt: midSeptember.addingTimeInterval(8 * 3600),
        refreshExpiresAt: midSeptember.addingTimeInterval(86_400)
    )

    private var rotated: TokenPair {
        TokenPair(
            access: "ghu_EXAMPLEaccess0002", refresh: "ghr_EXAMPLErefresh0002",
            accessExpiresAt: now.addingTimeInterval(28_800), refreshExpiresAt: now.addingTimeInterval(15_897_600)
        )
    }

    private func refresher(_ http: HTTPStub, store: MemoryTokenStore) -> TokenRefresher {
        TokenRefresher(
            refresher: DeviceFlow(clientID: "Iv23liEXAMPLE", transport: http.transport, userAgent: http.userAgent),
            store: store
        )
    }

    @Test func anExpiringTokenIsRotatedAndSavedBeforeUse() async throws {
        var expiring = original
        expiring.accessExpiresAt = now.addingTimeInterval(4 * 60)
        let store = MemoryTokenStore(expiring)
        let http = HTTPStub([.json(try fixture("token_rotated")), .json(try fixture("user"))])
        let client = UsageClient(transport: http.transport, userAgent: http.userAgent)
        let login = try await refresher(http, store: store).authorized(now: now) { accessToken in
            // Saved as one pair before the request runs.
            #expect(await store.pair == rotated)
            return try await client.currentLogin(accessToken: accessToken, now: now)
        }
        #expect(login == "octocat")
        #expect(await store.saves == [rotated])
        #expect(http.requests.map(\.url.path) == ["/login/oauth/access_token", "/user"])
        #expect(http.requests.last?.header("Authorization") == "Bearer ghu_EXAMPLEaccess0002")
    }

    @Test func aRejectedTokenRefreshesOnceAndRetriesOnce() async throws {
        let store = MemoryTokenStore(original)
        let http = HTTPStub([
            .http(401, #"{"message":"Bad credentials"}"#), .json(try fixture("token_rotated")),
            .json(try fixture("usage_openapi_example")),
        ])
        let client = UsageClient(transport: http.transport, userAgent: http.userAgent)
        let usage = try await refresher(http, store: store).authorized(now: now) { accessToken in
            try await client.usage(
                login: "octocat", accessToken: accessToken, plan: .pro, customAllowance: nil, now: now
            )
        }
        #expect(usage.status == .ok)
        #expect(await store.pair == rotated)
        #expect(http.requests.map(\.url.path) == [
            "/users/octocat/settings/billing/ai_credit/usage", "/login/oauth/access_token",
            "/users/octocat/settings/billing/ai_credit/usage",
        ])
        #expect(http.requests.map { $0.header("Authorization") } == [
            "Bearer ghu_EXAMPLEaccess0001", nil, "Bearer ghu_EXAMPLEaccess0002",
        ])
    }

    @Test func aSecond401IsSignInExpired() async throws {
        let store = MemoryTokenStore(original)
        let http = HTTPStub([.http(401, ""), .json(try fixture("token_rotated")), .http(401, "")])
        let client = UsageClient(transport: http.transport, userAgent: http.userAgent)
        await #expect(throws: TokenRefreshError.rejected) {
            try await refresher(http, store: store).authorized(now: now) {
                try await client.currentLogin(accessToken: $0, now: now)
            }
        }
        #expect(http.requests.count == 3)
    }

    @Test func aBadRefreshTokenIsSignInExpired() async throws {
        var expiring = original
        expiring.accessExpiresAt = now.addingTimeInterval(60)
        let store = MemoryTokenStore(expiring)
        let http = HTTPStub([.json(#"{"error":"bad_refresh_token"}"#)])
        let client = UsageClient(transport: http.transport, userAgent: http.userAgent)
        do {
            _ = try await refresher(http, store: store).authorized(now: now) {
                try await client.currentLogin(accessToken: $0, now: now)
            }
            Issue.record("Expected a rejected refresh")
        } catch {
            #expect(error as? TokenRefreshError == .rejected)
            #expect(CopilotUsageMapping.status(for: error) == .signInExpired)
        }
        #expect(await store.saves.isEmpty)
        #expect(http.requests.count == 1)
    }
}
