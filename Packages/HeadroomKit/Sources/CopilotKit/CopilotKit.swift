import Foundation
import HeadroomModel

// CopilotKit: this month's GitHub Copilot usage through Headroom's own GitHub App (1.1 §4.1–4.8). Foundation only.
//
// Pipeline: `DeviceFlow` signs in (§4.3) and hands back a `TokenPair`, which the app keeps in its own Keychain item
// through a `TokenStore`. A `TokenRefresher` keeps the pair usable and runs every API request with it. `UsageClient`
// then fetches the login and the billing usage (§4.4) and maps it to a Copilot `ToolUsage` with the allowance of
// the user's `CopilotPlan` (§4.5); `CopilotUsageMapping` keeps the last reading when a poll fails (§4.6) and
// `CopilotPollPolicy` decides when to poll (§4.7). Every request goes through an injected `HTTPTransport`. Tokens are
// never logged, printed, put in URLs or written anywhere but the `TokenStore`.

/// The plan picked in Settings › Copilot › Plan (§4.5): GitHub doesn't tell apps the allowance. Raw values are the
/// `copilotPlan` preference values.
public enum CopilotPlan: String, Sendable, Codable, CaseIterable {
    case notSure
    case pro
    case proPlus
    case max
    case legacyPro
    case legacyProPlus
    case custom

    /// The picker label.
    public var label: String {
        switch self {
        case .notSure: "Not sure: show usage only"
        case .pro: "Pro · 1,500 credits a month"
        case .proPlus: "Pro+ · 7,000 credits a month"
        case .max: "Max · 20,000 credits a month"
        case .legacyPro: "Pro, yearly on older billing · 300 requests"
        case .legacyProPlus: "Pro+, yearly on older billing · 1,500 requests"
        case .custom: "Custom…"
        }
    }

    /// The preset's name for `ToolUsage.planName` ("Pro+"); nil for Not sure and Custom.
    public var presetName: String? {
        switch self {
        case .pro, .legacyPro: "Pro"
        case .proPlus, .legacyProPlus: "Pro+"
        case .max: "Max"
        case .notSure, .custom: nil
        }
    }

    /// The unit the allowance counts; nil = detected from which endpoint has items (§4.4).
    public var unit: UsageUnit? {
        switch self {
        case .pro, .proPlus, .max: .aiCredits
        case .legacyPro, .legacyProPlus: .premiumRequests
        case .notSure, .custom: nil
        }
    }

    /// The preset allowance; nil for Not sure (no ring fill, no percent) and Custom (see `allowance(custom:)`).
    public var allowance: Double? {
        switch self {
        case .pro: 1_500
        case .proPlus: 7_000
        case .max: 20_000
        case .legacyPro: 300
        case .legacyProPlus: 1_500
        case .notSure, .custom: nil
        }
    }

    /// The valid `copilotCustomAllowance` values.
    public static let customAllowanceRange: ClosedRange<Double> = 1...1_000_000

    /// The allowance to compute percents with: the preset's, or for Custom the user's number when it lies in
    /// `customAllowanceRange` (else nil).
    public func allowance(custom: Double?) -> Double? {
        guard self == .custom else { return allowance }
        guard let custom, Self.customAllowanceRange.contains(custom) else { return nil }
        return custom
    }

    /// Legacy presets query only `premium_request/usage` (§4.4).
    public var isLegacy: Bool { self == .legacyPro || self == .legacyProPlus }
}

/// A GitHub App user access token and its refresh token (§4.3). Stored as one Keychain item, JSON
/// `{"access":"ghu_…","refresh":"ghr_…","accessExpiresAt":1790000000,"refreshExpiresAt":1805000000}` with epoch
/// seconds, whatever the encoder's date strategy. `description`, `debugDescription` and the mirror redact both tokens.
public struct TokenPair: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public var access: String
    public var refresh: String
    public var accessExpiresAt: Date
    public var refreshExpiresAt: Date

    public init(access: String, refresh: String, accessExpiresAt: Date, refreshExpiresAt: Date) {
        self.access = access
        self.refresh = refresh
        self.accessExpiresAt = accessExpiresAt
        self.refreshExpiresAt = refreshExpiresAt
    }

    /// Refresh when the access token expires within 5 minutes (§4.3).
    public func accessNeedsRefresh(now: Date) -> Bool {
        accessExpiresAt.addingTimeInterval(-5 * 60) < now
    }

    /// Past this, only a new sign-in helps: `.signInExpired`.
    public func refreshExpired(now: Date) -> Bool {
        refreshExpiresAt <= now
    }

    private enum CodingKeys: String, CodingKey {
        case access, refresh, accessExpiresAt, refreshExpiresAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        access = try container.decode(String.self, forKey: .access)
        refresh = try container.decode(String.self, forKey: .refresh)
        accessExpiresAt = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .accessExpiresAt))
        refreshExpiresAt = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .refreshExpiresAt))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(access, forKey: .access)
        try container.encode(refresh, forKey: .refresh)
        try container.encode(accessExpiresAt.timeIntervalSince1970, forKey: .accessExpiresAt)
        try container.encode(refreshExpiresAt.timeIntervalSince1970, forKey: .refreshExpiresAt)
    }

    public var description: String {
        "TokenPair(access: <redacted>, refresh: <redacted>, accessExpiresAt: \(accessExpiresAt), "
            + "refreshExpiresAt: \(refreshExpiresAt))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "access": "<redacted>", "refresh": "<redacted>",
                "accessExpiresAt": accessExpiresAt, "refreshExpiresAt": refreshExpiresAt,
            ],
            displayStyle: .struct
        )
    }
}

/// Where the token pair lives: the app's Keychain item (service `com.niomartinez.headroom.github`, account
/// `default`, §4.3), or memory in tests. `save` replaces the pair atomically, as one item.
public protocol TokenStore: Sendable {
    func load() async throws -> TokenPair?
    func save(_ pair: TokenPair) async throws
    func delete() async throws
}

/// Sends one request (injected so tests stub HTTP). Every request carries `User-Agent: Headroom/<version> (macOS)`
/// (`GitHubAPI.userAgent(appVersion:)`).
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// What every GitHub request shares.
public enum GitHubAPI {
    /// `Headroom/<version> (macOS)`: the `User-Agent` of every GitHub request (§4.3).
    public static func userAgent(appVersion: String) -> String {
        "Headroom/\(appVersion) (macOS)"
    }
}

/// `HTTPTransport` over a `URLSession`.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// The device code GitHub hands out (§4.3). `deviceCode` gets a token once the user approves, so `description`,
/// `debugDescription` and the mirror redact it like `TokenPair`'s tokens.
public struct DeviceCode: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var deviceCode: String
    /// What the user types at `verificationURI`, e.g. `WDJB-MJHT`.
    public var userCode: String
    public var verificationURI: URL
    public var expiresAt: Date
    /// Seconds between polls; grows by 5 on each `slow_down`.
    public var interval: TimeInterval

    public init(deviceCode: String, userCode: String, verificationURI: URL, expiresAt: Date, interval: TimeInterval) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURI = verificationURI
        self.expiresAt = expiresAt
        self.interval = interval
    }

    public var description: String {
        "DeviceCode(deviceCode: <redacted>, userCode: \(userCode), verificationURI: \(verificationURI), "
            + "expiresAt: \(expiresAt), interval: \(interval))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "deviceCode": "<redacted>", "userCode": userCode, "verificationURI": verificationURI,
                "expiresAt": expiresAt, "interval": interval,
            ],
            displayStyle: .struct
        )
    }
}

/// Why sign-in stopped (§4.3, §6.4 sheet errors). Refreshing throws `TokenRefreshError` instead.
public enum DeviceFlowError: Error, Sendable, Equatable {
    /// The device code's `expired_token`, or its `expires_in` passed: "The code expired. Try again."
    case expired
    /// `access_denied`: "You declined on GitHub."
    case denied
    /// `device_flow_disabled` or `incorrect_client_credentials`: "Sign-in with GitHub isn't available right now."
    case unavailable
    /// HTTP 429 or a `slow_down` storm: "GitHub is busy. Try again in a few minutes."
    case busy
    /// No connection or an unexpected answer.
    case failed
}

/// Why a refresh failed (§4.3, §4.6). Only `.rejected` ends the sign-in: a network blip keeps the stored pair.
public enum TokenRefreshError: Error, Sendable, Equatable {
    /// Nothing is stored: GitHub isn't connected.
    case notSignedIn
    /// `bad_refresh_token` (or any other OAuth error answer), a refresh token past `refreshExpiresAt`, or a 401 right
    /// after a refresh: only a new sign-in helps.
    case rejected
    /// No connection, a 5xx or an answer that can't be read: the stored pair is kept; back off and try again.
    case offline
    /// HTTP 403/429: the stored pair is kept; wait `retryAfter` (Retry-After, else x-ratelimit-reset) when known.
    case rateLimited(retryAfter: TimeInterval?)

    /// What Copilot shows (§4.6): `.notConnected`, `.signInExpired`, `.offline` or `.rateLimited`.
    public var status: ToolStatus {
        switch self {
        case .notSignedIn: .notConnected
        case .rejected: .signInExpired
        case .offline: .offline
        case .rateLimited: .rateLimited
        }
    }
}

/// Exchanges a pair's refresh token for a new pair; both tokens rotate (§4.3). `DeviceFlow` does it against GitHub;
/// tests pass a fake.
public protocol TokenRefreshing: Sendable {
    /// Throws `TokenRefreshError`.
    func refresh(_ pair: TokenPair, now: Date) async throws -> TokenPair
}

/// Keeps GitHub requests signed in (§4.3): `authorized` refreshes the pair when its access token expires within
/// 5 minutes, or once after a 401, saves the rotated pair through the `TokenStore` before anything uses it, and
/// retries the request once. Refreshes never overlap: both tokens rotate, so a second refresh with the spent token
/// would get `bad_refresh_token` and sign the user out.
///
/// Only the main app's `CopilotService` has one, and it signs in and out through it, so the pair kept in memory is
/// the stored one. Errors are `TokenRefreshError`s, the request's own errors, or the store's, rethrown as they are.
public actor TokenRefresher {
    private let refresher: any TokenRefreshing
    private let store: any TokenStore
    /// The stored pair once `loaded` (nil = nothing stored).
    private var pair: TokenPair?
    private var loaded = false
    /// The refresh that is running, which every caller shares.
    private var refreshing: Task<TokenPair, any Error>?

    public init(refresher: any TokenRefreshing, store: any TokenStore) {
        self.refresher = refresher
        self.store = store
    }

    /// Runs `request` with a usable access token. When it throws `UsageClientError.unauthorized`, refreshes once
    /// and runs it once more; a second 401 throws `TokenRefreshError.rejected`.
    public func authorized<Value: Sendable>(
        now: Date, _ request: @Sendable (_ accessToken: String) async throws -> Value
    ) async throws -> Value {
        let first = try await usablePair(now: now, rejectedAccess: nil)
        do {
            return try await request(first.access)
        } catch UsageClientError.unauthorized {
            let second = try await usablePair(now: now, rejectedAccess: first.access)
            do {
                return try await request(second.access)
            } catch UsageClientError.unauthorized {
                throw TokenRefreshError.rejected
            }
        }
    }

    /// Keeps a new sign-in's pair (`DeviceFlow.waitForToken`), after any refresh that is running.
    public func signIn(with newPair: TokenPair) async throws {
        if let refreshing { _ = try? await refreshing.value }
        pair = newPair
        loaded = true
        try await store.save(newPair)
    }

    /// Disconnect: forgets and deletes the stored pair, after any refresh that is running.
    public func signOut() async throws {
        if let refreshing { _ = try? await refreshing.value }
        pair = nil
        loaded = true
        try await store.delete()
    }

    /// The stored pair, refreshed first when its access token expires within 5 minutes or is `rejectedAccess` (it
    /// just got a 401).
    private func usablePair(now: Date, rejectedAccess: String?) async throws -> TokenPair {
        if let refreshing { return try await refreshing.value }
        guard let current = try await storedPair() else { throw TokenRefreshError.notSignedIn }
        // One may have started while the store loaded.
        if let refreshing { return try await refreshing.value }
        guard current.accessNeedsRefresh(now: now) || current.access == rejectedAccess else { return current }
        guard !current.refreshExpired(now: now) else { throw TokenRefreshError.rejected }
        // Runs on this actor: it saves and keeps the rotated pair before any caller gets it, and before a sign-in
        // or sign-out waiting for it goes on.
        let task = Task { () async throws -> TokenPair in
            defer { self.refreshing = nil }
            let rotated = try await self.refresher.refresh(current, now: now)
            try await self.store.save(rotated)
            self.pair = rotated
            return rotated
        }
        refreshing = task
        return try await task.value
    }

    private func storedPair() async throws -> TokenPair? {
        if !loaded {
            let stored = try await store.load()
            // A sign-in or sign-out while the store loaded wins.
            if !loaded {
                pair = stored
                loaded = true
            }
        }
        return pair
    }
}

/// Why an API request (`UsageClient`) failed (§4.6, §4.7).
public enum UsageClientError: Error, Sendable, Equatable {
    /// HTTP 401: `TokenRefresher.authorized` refreshes once and retries the request once.
    case unauthorized
    /// HTTP 403/429: keep the last reading (`.rateLimited`) and wait `retryAfter` (Retry-After, else
    /// x-ratelimit-reset) when known.
    case rateLimited(retryAfter: TimeInterval?)
    /// A network error or a 5xx: keep the last reading (`.offline`) and back off.
    case offline
    /// Anything else unexpected: another status (404, 422, …), or a 200 whose body isn't a usage report
    /// (`statusCode` 200). GitHub did answer, so Copilot shows `.unrecognized`, not `.offline`.
    case unexpectedResponse(statusCode: Int)
}
