import Foundation
import HeadroomModel
import Testing
@testable import CopilotKit

/// The public contract other streams build against (1.1 §4.3, §4.5).
@Suite struct CopilotContractTests {
    @Test func planAllowances() {
        #expect(CopilotPlan.allCases.map(\.rawValue)
            == ["notSure", "pro", "proPlus", "max", "legacyPro", "legacyProPlus", "custom"])
        #expect(CopilotPlan.allCases.map(\.allowance) == [nil, 1_500, 7_000, 20_000, 300, 1_500, nil])
        #expect(CopilotPlan.pro.unit == .aiCredits)
        #expect(CopilotPlan.legacyProPlus.unit == .premiumRequests)
        #expect(CopilotPlan.notSure.unit == nil)
        #expect(CopilotPlan.proPlus.presetName == "Pro+")
        #expect(CopilotPlan.custom.allowance(custom: 2_500) == 2_500)
        #expect(CopilotPlan.custom.allowance(custom: 0) == nil)
        #expect(CopilotPlan.custom.allowance(custom: nil) == nil)
        #expect(CopilotPlan.max.allowance(custom: 5) == 20_000)
        #expect(CopilotPlan.legacyPro.isLegacy && !CopilotPlan.pro.isLegacy)
    }

    @Test func tokenPairStoresEpochSeconds() throws {
        let pair = TokenPair(
            access: "ghu_EXAMPLE", refresh: "ghr_EXAMPLE",
            accessExpiresAt: Date(timeIntervalSince1970: 1_790_000_000),
            refreshExpiresAt: Date(timeIntervalSince1970: 1_805_000_000)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(pair), as: UTF8.self)
        #expect(json == #"{"access":"ghu_EXAMPLE","accessExpiresAt":1790000000,"refresh":"ghr_EXAMPLE","refreshExpiresAt":1805000000}"#)
        #expect(try JSONDecoder().decode(TokenPair.self, from: Data(json.utf8)) == pair)
    }

    @Test func tokenPairNeverPrintsItsTokens() {
        let pair = TokenPair(
            access: "ghu_EXAMPLE", refresh: "ghr_EXAMPLE",
            accessExpiresAt: Date(timeIntervalSince1970: 1_790_000_000),
            refreshExpiresAt: Date(timeIntervalSince1970: 1_805_000_000)
        )
        var dumped = ""
        dump(pair, to: &dumped)
        for text in [pair.description, pair.debugDescription, "\(pair)", String(reflecting: pair), dumped] {
            #expect(!text.contains("ghu_EXAMPLE"))
            #expect(!text.contains("ghr_EXAMPLE"))
        }
    }

    @Test func deviceCodeNeverPrintsItsCode() throws {
        let code = DeviceCode(
            deviceCode: "3584d8EXAMPLE", userCode: "WDJB-MJHT",
            verificationURI: try #require(URL(string: "https://github.com/login/device")),
            expiresAt: Date(timeIntervalSince1970: 1_790_000_900), interval: 5
        )
        var dumped = ""
        dump(code, to: &dumped)
        for text in [code.description, code.debugDescription, "\(code)", String(reflecting: code), dumped] {
            #expect(!text.contains("3584d8EXAMPLE"))
            #expect(text.contains("WDJB-MJHT"))
        }
    }

    @Test func refreshErrorStatuses() {
        #expect(TokenRefreshError.notSignedIn.status == .notConnected)
        #expect(TokenRefreshError.rejected.status == .signInExpired)
        #expect(TokenRefreshError.offline.status == .offline)
        #expect(TokenRefreshError.rateLimited(retryAfter: 60).status == .rateLimited)
    }

    @Test func refreshTiming() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let pair = TokenPair(
            access: "a", refresh: "r", accessExpiresAt: now.addingTimeInterval(6 * 60),
            refreshExpiresAt: now.addingTimeInterval(3600)
        )
        #expect(!pair.accessNeedsRefresh(now: now))
        #expect(pair.accessNeedsRefresh(now: now.addingTimeInterval(61)))
        #expect(!pair.refreshExpired(now: now))
        #expect(pair.refreshExpired(now: now.addingTimeInterval(3600)))
    }
}

@Test func userAgentNamesTheApp() {
    #expect(GitHubAPI.userAgent(appVersion: "1.1.0") == "Headroom/1.1.0 (macOS)")
}

/// `TokenRefresher` (1.1 §4.3): refresh before expiry or once after a 401, save before use, never two at once.
@Suite struct TokenRefresherTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func pair(_ name: String, accessExpiresIn: TimeInterval = 8 * 3600, refreshExpiresIn: TimeInterval = 86_400)
        -> TokenPair
    {
        TokenPair(
            access: "ghu_\(name)", refresh: "ghr_\(name)", accessExpiresAt: now.addingTimeInterval(accessExpiresIn),
            refreshExpiresAt: now.addingTimeInterval(refreshExpiresIn)
        )
    }

    private actor MemoryStore: TokenStore {
        private(set) var pair: TokenPair?
        private(set) var saves: [TokenPair] = []

        init(_ pair: TokenPair?) { self.pair = pair }

        func load() async throws -> TokenPair? { pair }
        func save(_ pair: TokenPair) async throws {
            self.pair = pair
            saves.append(pair)
        }
        func delete() async throws { pair = nil }
    }

    /// Answers each refresh with the next result; after `hold()`, refreshes wait until `release()`.
    private actor FakeRefresher: TokenRefreshing {
        private var results: [Result<TokenPair, TokenRefreshError>]
        private(set) var calls: [TokenPair] = []
        private var holds = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        init(_ results: [Result<TokenPair, TokenRefreshError>]) { self.results = results }

        func hold() { holds = true }

        func release() {
            holds = false
            waiting.forEach { $0.resume() }
            waiting = []
        }

        func refresh(_ pair: TokenPair, now: Date) async throws -> TokenPair {
            calls.append(pair)
            if holds { await withCheckedContinuation { waiting.append($0) } }
            guard !results.isEmpty else {
                Issue.record("Unexpected refresh")
                throw TokenRefreshError.offline
            }
            return try results.removeFirst().get()
        }
    }

    /// The access tokens requests were made with, and which of them GitHub answers with 401.
    private actor FakeAPI {
        private let rejected: Set<String>
        private(set) var tokens: [String] = []

        init(rejecting rejected: Set<String> = []) { self.rejected = rejected }

        func call(_ token: String) throws -> String {
            tokens.append(token)
            if rejected.contains(token) { throw UsageClientError.unauthorized }
            return "octocat"
        }
    }

    @Test func freshTokenIsUsedAsItIs() async throws {
        let refresher = FakeRefresher([])
        let refresh = TokenRefresher(refresher: refresher, store: MemoryStore(pair("a")))
        let api = FakeAPI()
        #expect(try await refresh.authorized(now: now) { try await api.call($0) } == "octocat")
        #expect(await api.tokens == ["ghu_a"])
        #expect(await refresher.calls.isEmpty)
    }

    @Test func refreshesBeforeExpiryAndSavesBeforeUse() async throws {
        let store = MemoryStore(pair("a", accessExpiresIn: 4 * 60))
        let refresher = FakeRefresher([.success(pair("b"))])
        let refresh = TokenRefresher(refresher: refresher, store: store)
        let stored = try await refresh.authorized(now: now) { _ in await store.pair }
        #expect(stored == pair("b"))
        #expect(await store.saves == [pair("b")])
        #expect(await refresher.calls == [pair("a", accessExpiresIn: 4 * 60)])
        // The rotated pair is kept: no second refresh.
        let api = FakeAPI()
        _ = try await refresh.authorized(now: now) { try await api.call($0) }
        #expect(await api.tokens == ["ghu_b"])
        #expect(await refresher.calls.count == 1)
    }

    @Test func unauthorizedRefreshesOnceAndRetriesOnce() async throws {
        let store = MemoryStore(pair("a"))
        let refresher = FakeRefresher([.success(pair("b"))])
        let refresh = TokenRefresher(refresher: refresher, store: store)
        let api = FakeAPI(rejecting: ["ghu_a"])
        #expect(try await refresh.authorized(now: now) { try await api.call($0) } == "octocat")
        #expect(await api.tokens == ["ghu_a", "ghu_b"])
        #expect(await refresher.calls.count == 1)
        #expect(await store.pair == pair("b"))
    }

    @Test func unauthorizedAfterARefreshIsSignInExpired() async throws {
        let refresher = FakeRefresher([.success(pair("b"))])
        let refresh = TokenRefresher(refresher: refresher, store: MemoryStore(pair("a")))
        let api = FakeAPI(rejecting: ["ghu_a", "ghu_b"])
        await #expect(throws: TokenRefreshError.rejected) {
            try await refresh.authorized(now: now) { try await api.call($0) }
        }
        #expect(await api.tokens == ["ghu_a", "ghu_b"])
        #expect(await refresher.calls.count == 1)
    }

    @Test func rejectedRefreshIsSignInExpired() async throws {
        let expiring = pair("a", accessExpiresIn: 60)
        let store = MemoryStore(expiring)
        let refresh = TokenRefresher(refresher: FakeRefresher([.failure(.rejected)]), store: store)
        let api = FakeAPI()
        await #expect(throws: TokenRefreshError.rejected) {
            try await refresh.authorized(now: now) { try await api.call($0) }
        }
        #expect(await api.tokens.isEmpty)
        #expect(await store.saves.isEmpty)
    }

    /// A network blip while refreshing keeps the stored pair, so the next poll can try again.
    @Test func offlineRefreshKeepsThePair() async throws {
        let expiring = pair("a", accessExpiresIn: 60)
        let store = MemoryStore(expiring)
        let refresher = FakeRefresher([.failure(.offline), .success(pair("b"))])
        let refresh = TokenRefresher(refresher: refresher, store: store)
        let api = FakeAPI()
        await #expect(throws: TokenRefreshError.offline) {
            try await refresh.authorized(now: now) { try await api.call($0) }
        }
        #expect(await store.pair == expiring)
        _ = try await refresh.authorized(now: now) { try await api.call($0) }
        #expect(await api.tokens == ["ghu_b"])
        #expect(await refresher.calls == [expiring, expiring])
    }

    @Test func expiredRefreshTokenNeedsANewSignIn() async throws {
        let refresher = FakeRefresher([])
        let store = MemoryStore(pair("a", accessExpiresIn: -60, refreshExpiresIn: -1))
        let refresh = TokenRefresher(refresher: refresher, store: store)
        await #expect(throws: TokenRefreshError.rejected) {
            try await refresh.authorized(now: now) { $0 }
        }
        #expect(await refresher.calls.isEmpty)
    }

    @Test func signInAndOut() async throws {
        let store = MemoryStore(nil)
        let refresh = TokenRefresher(refresher: FakeRefresher([]), store: store)
        await #expect(throws: TokenRefreshError.notSignedIn) {
            try await refresh.authorized(now: now) { $0 }
        }
        try await refresh.signIn(with: pair("a"))
        #expect(await store.pair == pair("a"))
        #expect(try await refresh.authorized(now: now) { $0 } == "ghu_a")
        try await refresh.signOut()
        #expect(await store.pair == nil)
        await #expect(throws: TokenRefreshError.notSignedIn) {
            try await refresh.authorized(now: now) { $0 }
        }
    }

    /// Two requests at once with an expiring token share one refresh: a second one would spend the rotated
    /// refresh token again and get `bad_refresh_token`.
    @Test(.timeLimit(.minutes(1))) func concurrentRequestsShareOneRefresh() async throws {
        let store = MemoryStore(pair("a", accessExpiresIn: 60))
        let refresher = FakeRefresher([.success(pair("b")), .failure(.rejected)])
        await refresher.hold()
        let refresh = TokenRefresher(refresher: refresher, store: store)
        let first = Task { try await refresh.authorized(now: now) { $0 } }
        while await refresher.calls.isEmpty { await Task.yield() }
        let second = Task { try await refresh.authorized(now: now) { $0 } }
        for _ in 0..<200 { await Task.yield() }
        await refresher.release()
        #expect(try await first.value == "ghu_b")
        #expect(try await second.value == "ghu_b")
        #expect(await refresher.calls.count == 1)
        #expect(await store.saves == [pair("b")])
    }
}
