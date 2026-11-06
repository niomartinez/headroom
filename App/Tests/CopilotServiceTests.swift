import CopilotKit
import Foundation
import HeadroomModel
import os
import Testing

/// `CopilotService` (1.1 §4.3–§4.7) against a made-up GitHub: every answer below is synthetic, the tokens are fake
/// and nothing leaves the process.
@Suite struct CopilotServiceTests {
    /// Answers by URL path; records what was asked.
    struct FakeGitHub: HTTPTransport {
        let answer: @Sendable (_ method: String, _ path: String) -> (status: Int, body: String)
        let seen = OSAllocatedUnfairLock<[String]>(initialState: [])

        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            guard let url = request.url else { throw URLError(.badURL) }
            let method = request.httpMethod ?? "GET"
            seen.withLock { $0.append("\(method) \(url.path)") }
            let (status, body) = answer(method, url.path)
            guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
            else { throw URLError(.badServerResponse) }
            return (Data(body.utf8), response)
        }

        var requests: [String] { seen.withLock { $0 } }
    }

    actor MemoryStore: TokenStore {
        private(set) var pair: TokenPair?

        init(_ pair: TokenPair? = nil) {
            self.pair = pair
        }

        func load() async throws -> TokenPair? { pair }
        func save(_ pair: TokenPair) async throws { self.pair = pair }
        func delete() async throws { pair = nil }
    }

    private static let accessToken = "ghu_FAKEACCESS000"
    private static let refreshToken = "ghr_FAKEREFRESH000"

    private static var validPair: TokenPair {
        TokenPair(
            access: accessToken, refresh: refreshToken,
            accessExpiresAt: Date().addingTimeInterval(8 * 3600), refreshExpiresAt: Date().addingTimeInterval(180 * 86400)
        )
    }

    /// 512 AI credits this month.
    private static let creditsBody = #"{"timePeriod":{"year":2026,"month":9},"user":"octocat","usageItems":[{"product":"Copilot AI Credits","sku":"AI Credit","model":"GPT-5","unitType":"ai-credits","pricePerUnit":0.01,"grossQuantity":512,"grossAmount":5.12,"discountQuantity":512,"discountAmount":5.12,"netQuantity":0,"netAmount":0}]}"#

    private static func github(billing: @escaping @Sendable () -> (Int, String) = { (200, creditsBody) }) -> FakeGitHub {
        FakeGitHub { method, path in
            switch (method, path) {
            case ("POST", "/login/device/code"):
                return (200, #"{"device_code":"FAKEDEVICE","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#)
            case ("POST", "/login/oauth/access_token"):
                return (200, #"{"access_token":"\#(accessToken)","expires_in":28800,"refresh_token":"\#(refreshToken)","refresh_token_expires_in":15897600,"token_type":"bearer","scope":""}"#)
            case ("GET", "/user"):
                return (200, #"{"login":"octocat","id":1,"type":"User"}"#)
            case ("GET", let path) where path.hasPrefix("/users/octocat/settings/billing/"):
                return billing()
            default:
                return (404, #"{"message":"Not Found"}"#)
            }
        }
    }

    private func service(
        _ github: FakeGitHub, store: MemoryStore, login: String? = "octocat", plan: CopilotPlan = .pro
    ) -> CopilotService {
        let userAgent = GitHubAPI.userAgent(appVersion: "1.1.0")
        let flow = DeviceFlow(
            clientID: "Iv23liEXAMPLE", transport: github, userAgent: userAgent, clock: { Date() }, sleep: { _ in }
        )
        return CopilotService(
            deviceFlow: flow, store: store, client: UsageClient(transport: github, userAgent: userAgent),
            login: login, plan: plan, customAllowance: nil
        )
    }

    // MARK: Polling

    @Test func withoutAStoredPairCopilotIsNotConnected() async throws {
        let github = Self.github()
        let outcome = try #require(await service(github, store: MemoryStore()).poll(.timer, now: Date()))
        #expect(outcome.usage.status == .notConnected)
        #expect(!outcome.succeeded)
        #expect(github.requests.isEmpty)
    }

    @Test func aPollReadsThisMonthsCreditsAgainstThePlan() async throws {
        let github = Self.github()
        let service = service(github, store: MemoryStore(Self.validPair))
        let now = Date()
        let outcome = try #require(await service.poll(.timer, now: now))
        #expect(outcome.succeeded)
        #expect(outcome.fetchedLogin == nil)
        #expect(outcome.usage.status == .ok)
        #expect(outcome.usage.account == "octocat")
        #expect(outcome.usage.planName == "Pro")
        let limit = try #require(outcome.usage.limits.first)
        #expect(limit.window == .monthly)
        #expect(limit.used == 512)
        #expect(limit.allowance == 1_500)
        #expect(limit.usedPercent.map { ($0 * 100).rounded() / 100 } == 34.13)
        #expect(github.requests.contains { $0.hasPrefix("GET /users/octocat/settings/billing/ai_credit/usage") })

        // The next timer poll waits its 15 minutes.
        #expect(await service.poll(.timer, now: now.addingTimeInterval(60)) == nil)
        #expect(await service.nextTimerPoll(now: now) == now.addingTimeInterval(CopilotPollPolicy.interval))
    }

    @Test func theLoginIsFetchedWhenNoneIsKnown() async throws {
        let github = Self.github()
        let outcome = try #require(await service(github, store: MemoryStore(Self.validPair), login: nil).poll(.timer, now: Date()))
        #expect(outcome.fetchedLogin == "octocat")
        #expect(outcome.usage.account == "octocat")
        #expect(github.requests.first == "GET /user")
    }

    /// Offline keeps the last reading, to be shown dimmed with "as of" (1.1 §4.6).
    @Test func aFailureKeepsTheLastReading() async throws {
        let failing = OSAllocatedUnfairLock(initialState: false)
        let github = Self.github { failing.withLock { $0 } ? (503, "") : (200, Self.creditsBody) }
        let service = service(github, store: MemoryStore(Self.validPair))
        let now = Date()
        _ = try #require(await service.poll(.timer, now: now))

        failing.withLock { $0 = true }
        let outcome = try #require(await service.poll(.wake, now: now.addingTimeInterval(60)))
        #expect(!outcome.succeeded)
        #expect(outcome.usage.status == .offline)
        #expect(outcome.usage.limits.first?.used == 512)
        // Backing off: the next timer poll isn't before a minute.
        #expect(await service.nextTimerPoll(now: now.addingTimeInterval(60)) >= now.addingTimeInterval(120))
    }

    @Test func noItemsThisMonthIsNoIndividualUsage() async throws {
        let github = Self.github { (200, #"{"timePeriod":{"year":2026,"month":9},"user":"octocat","usageItems":[]}"#) }
        let outcome = try #require(await service(github, store: MemoryStore(Self.validPair)).poll(.timer, now: Date()))
        #expect(outcome.succeeded)
        #expect(outcome.usage.status == .noIndividualUsage)
    }

    /// The GitHub account was renamed after sign-in: the saved login 404s, so `/user` is asked again and the poll
    /// goes on with the new login, which the app then saves.
    @Test func aRenamedAccountIsFollowed() async throws {
        let github = FakeGitHub { method, path in
            switch (method, path) {
            case ("GET", "/user"): (200, #"{"login":"octocat-renamed","id":1,"type":"User"}"#)
            case ("GET", let path) where path.hasPrefix("/users/octocat-renamed/settings/billing/"): (200, Self.creditsBody)
            default: (404, #"{"message":"Not Found"}"#)
            }
        }
        let service = service(github, store: MemoryStore(Self.validPair))
        let outcome = try #require(await service.poll(.timer, now: Date()))
        #expect(outcome.succeeded)
        #expect(outcome.fetchedLogin == "octocat-renamed")
        #expect(outcome.usage.account == "octocat-renamed")
        #expect(outcome.usage.limits.first?.used == 512)
        #expect(github.requests == [
            "GET /users/octocat/settings/billing/ai_credit/usage", "GET /user",
            "GET /users/octocat-renamed/settings/billing/ai_credit/usage",
        ])
    }

    /// Any other answer that isn't usage (a 404 for the same login, a 422): GitHub did answer, so not "Can't reach
    /// GitHub" but an unrecognized answer, without numbers, and backed off.
    @Test(arguments: [404, 410, 422])
    func aClientErrorIsNotOffline(status: Int) async throws {
        let github = Self.github { (status, #"{"message":"Nope"}"#) }
        let service = service(github, store: MemoryStore(Self.validPair))
        let now = Date()
        let outcome = try #require(await service.poll(.timer, now: now))
        #expect(!outcome.succeeded)
        #expect(outcome.usage.status == .unrecognized)
        #expect(outcome.usage.limits.isEmpty)
        #expect(outcome.fetchedLogin == nil)
        #expect(github.requests.filter { $0.contains("/billing/") }.count == 1)
        #expect(await service.nextTimerPoll(now: now) >= now.addingTimeInterval(60))
    }

    @Test func thePlanPickerAppliesToTheLastReadingAtOnce() async throws {
        let service = service(Self.github(), store: MemoryStore(Self.validPair), plan: .notSure)
        let outcome = try #require(await service.poll(.timer, now: Date()))
        #expect(outcome.usage.limits.first?.usedPercent == nil)

        let proPlus = try #require(await service.setPlan(.proPlus, customAllowance: nil))
        #expect(proPlus.limits.first?.allowance == 7_000)
        #expect(proPlus.planName == "Pro+")
        let custom = try #require(await service.setPlan(.custom, customAllowance: 1_024))
        #expect(custom.limits.first?.usedPercent == 50)
    }

    // MARK: Signing in and out

    @Test func signingInKeepsThePairAndNamesTheLogin() async throws {
        let github = Self.github()
        let store = MemoryStore()
        let service = service(github, store: store, login: nil)

        let code = try await service.requestCode(now: Date())
        #expect(code.userCode == "WDJB-MJHT")
        let login = try await service.signIn(with: code)
        #expect(login == "octocat")
        #expect(await store.pair?.access == Self.accessToken)

        // A sign-in fetches at once, whatever the backoff.
        let outcome = try #require(await service.poll(.signedIn, now: Date()))
        #expect(outcome.usage.status == .ok)
        #expect(outcome.fetchedLogin == nil)
    }

    /// A sign-in whose login can't be fetched leaves no token behind.
    @Test func aSignInWithoutALoginDeletesTheNewPair() async throws {
        let github = FakeGitHub { method, path in
            switch (method, path) {
            case ("POST", "/login/oauth/access_token"):
                (200, #"{"access_token":"\#(Self.accessToken)","expires_in":28800,"refresh_token":"\#(Self.refreshToken)","refresh_token_expires_in":15897600}"#)
            default:
                (500, "")
            }
        }
        let store = MemoryStore()
        let code = DeviceCode(
            deviceCode: "FAKEDEVICE", userCode: "WDJB-MJHT", verificationURI: URL(string: "https://github.com/login/device")!,
            expiresAt: Date().addingTimeInterval(900), interval: 5
        )
        await #expect(throws: DeviceFlowError.failed) {
            try await service(github, store: store, login: nil).signIn(with: code)
        }
        #expect(await store.pair == nil)
    }

    @Test func signingOutDeletesThePair() async throws {
        let store = MemoryStore(Self.validPair)
        let service = service(Self.github(), store: store)
        _ = try #require(await service.poll(.timer, now: Date()))

        try await service.signOut()
        #expect(await store.pair == nil)
        let outcome = try #require(await service.poll(.wake, now: Date()))
        #expect(outcome.usage.status == .notConnected)
    }

    /// Tokens never reach what the app shows, logs or hands to the widgets (1.1 §4.3).
    @Test func tokensNeverReachTheUsage() async throws {
        let service = service(Self.github(), store: MemoryStore(Self.validPair))
        let outcome = try #require(await service.poll(.timer, now: Date()))
        let encoded = String(decoding: try JSONEncoder().encode(outcome.usage), as: UTF8.self)
        for text in [encoded, String(describing: outcome), String(reflecting: outcome)] {
            #expect(!text.contains(Self.accessToken))
            #expect(!text.contains(Self.refreshToken))
        }
    }
}
