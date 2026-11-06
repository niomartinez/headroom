import Foundation

/// GitHub's OAuth device flow for Headroom's GitHub App (§4.3): no client secret, even for refresh.
///
/// Every parameter goes in a form body, never in the URL (§4.3: tokens are never put in URLs). Errors carry no
/// token, code or response text.
public struct DeviceFlow: TokenRefreshing {
    /// The GitHub App's Client ID (`Iv23…`, Info.plist `HeadroomGitHubClientID`). Not a secret.
    public let clientID: String
    private let transport: any HTTPTransport
    private let userAgent: String
    private let clock: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    /// Seconds added to the poll interval on each `slow_down` (§4.3).
    public static let slowDownStep: TimeInterval = 5
    /// The longest poll interval believed from GitHub (it sends 5 s, plus 5 s per `slow_down`) [J]: the code expires
    /// in 15 minutes anyway, and a huge value would overflow the sleep (`Duration.seconds` traps).
    static let maximumInterval: TimeInterval = 60
    /// More `slow_down` answers than this in one sign-in is a storm: "GitHub is busy" (§4.7) [J].
    static let maximumSlowDowns = 3
    /// Network errors or 5xx answers in a row while polling before sign-in gives up with `.failed` [J].
    static let maximumTransientFailures = 3

    public init(clientID: String, transport: any HTTPTransport, userAgent: String) {
        self.init(
            clientID: clientID, transport: transport, userAgent: userAgent, clock: { Date() },
            sleep: { try await Task.sleep(for: .seconds($0)) }
        )
    }

    /// `clock` and `sleep` are injected so tests don't wait. `sleep` must throw when the task is cancelled.
    public init(
        clientID: String, transport: any HTTPTransport, userAgent: String, clock: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void
    ) {
        self.clientID = clientID
        self.transport = transport
        self.userAgent = userAgent
        self.clock = clock
        self.sleep = sleep
    }

    /// `POST https://github.com/login/device/code`: the code to show in the Connect GitHub sheet (§6.4). Throws
    /// `DeviceFlowError`: 429 or `slow_down` → `.busy`; `device_flow_disabled`, `incorrect_client_credentials` or
    /// another 4xx → `.unavailable`; anything else → `.failed`.
    public func requestCode(now: Date) async throws -> DeviceCode {
        let request = URLRequest.gitHubOAuthForm(
            GitHubEndpoint.deviceCode, [("client_id", clientID)], userAgent: userAgent
        )
        let (data, response) = try await send(request, with: transport, failure: DeviceFlowError.failed)
        if response.statusCode == 429 { throw DeviceFlowError.busy }
        let answer = OAuthAnswer.decode(data)
        if let error = answer?.error {
            // An unknown client gets a 404 `{"error":"Not Found"}`.
            let mapped = DeviceFlowError(oauthError: error)
            throw mapped == .failed && (400..<500).contains(response.statusCode) ? DeviceFlowError.unavailable : mapped
        }
        guard response.statusCode == 200 else {
            throw (400..<500).contains(response.statusCode) ? DeviceFlowError.unavailable : DeviceFlowError.failed
        }
        guard let answer, let deviceCode = answer.deviceCode, !deviceCode.isEmpty,
            let userCode = answer.userCode, !userCode.isEmpty,
            let uri = answer.verificationURI.flatMap(URL.init(string:)), uri.scheme == "https",
            let expiresIn = answer.expiresIn, expiresIn > 0
        else { throw DeviceFlowError.failed }
        return DeviceCode(
            deviceCode: deviceCode, userCode: userCode, verificationURI: uri,
            expiresAt: now.addingTimeInterval(expiresIn), interval: Self.interval(answer.interval ?? 5)
        )
    }

    /// Polls `POST https://github.com/login/oauth/access_token` at `code.interval` (+5 s on each `slow_down`) until
    /// the user answers or the code expires, and returns the new pair. Throws `DeviceFlowError` (`.expired`,
    /// `.denied`, `.unavailable`, `.busy`, `.failed`), or `CancellationError` when the task is cancelled (the
    /// sheet's Cancel).
    public func waitForToken(_ code: DeviceCode) async throws -> TokenPair {
        var interval = code.interval
        var slowDowns = 0
        var transientFailures = 0
        while true {
            try await sleep(interval)
            guard clock() < code.expiresAt else { throw DeviceFlowError.expired }
            let request = URLRequest.gitHubOAuthForm(
                GitHubEndpoint.accessToken,
                [
                    ("client_id", clientID), ("device_code", code.deviceCode),
                    ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
                ],
                userAgent: userAgent
            )
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await send(request, with: transport, failure: DeviceFlowError.failed)
            } catch DeviceFlowError.failed {
                transientFailures += 1
                guard transientFailures < Self.maximumTransientFailures else { throw DeviceFlowError.failed }
                continue
            }
            if response.statusCode == 429 { throw DeviceFlowError.busy }
            let answer = OAuthAnswer.decode(data)
            if let pair = answer?.tokenPair(now: clock()) { return pair }
            switch answer?.error {
            case "authorization_pending":
                transientFailures = 0
            case "slow_down":
                transientFailures = 0
                slowDowns += 1
                guard slowDowns <= Self.maximumSlowDowns else { throw DeviceFlowError.busy }
                interval = Self.interval(max(interval + Self.slowDownStep, answer?.interval ?? 0))
            case let error?:
                throw DeviceFlowError(oauthError: error)
            case nil where (500..<600).contains(response.statusCode):
                transientFailures += 1
                guard transientFailures < Self.maximumTransientFailures else { throw DeviceFlowError.failed }
            case nil:
                throw DeviceFlowError.failed
            }
        }
    }

    /// A poll interval from GitHub, within 1 s…`maximumInterval`.
    static func interval(_ seconds: TimeInterval) -> TimeInterval {
        seconds.isFinite ? min(max(1, seconds), maximumInterval) : maximumInterval
    }

    /// `POST https://github.com/login/oauth/access_token` with `grant_type=refresh_token`: a new pair (both rotate).
    /// Throws `TokenRefreshError`: `bad_refresh_token` and any other OAuth error answer, or a refresh token past its
    /// expiry → `.rejected`; 403/429 → `.rateLimited`; anything else → `.offline`. `TokenRefresher` decides when to
    /// call it.
    public func refresh(_ pair: TokenPair, now: Date) async throws -> TokenPair {
        guard !pair.refresh.isEmpty, !pair.refreshExpired(now: now) else { throw TokenRefreshError.rejected }
        let request = URLRequest.gitHubOAuthForm(
            GitHubEndpoint.accessToken,
            [("client_id", clientID), ("grant_type", "refresh_token"), ("refresh_token", pair.refresh)],
            userAgent: userAgent
        )
        let (data, response) = try await send(request, with: transport, failure: TokenRefreshError.offline)
        if response.statusCode == 403 || response.statusCode == 429 {
            throw TokenRefreshError.rateLimited(retryAfter: RateLimitHeaders.retryAfter(response, now: now))
        }
        let answer = OAuthAnswer.decode(data)
        if let rotated = answer?.tokenPair(now: now) { return rotated }
        if answer?.error != nil { throw TokenRefreshError.rejected }
        throw TokenRefreshError.offline
    }
}

extension DeviceFlowError {
    /// The Connect GitHub sheet's copy (§6.4).
    public var message: String {
        switch self {
        case .denied: "You declined on GitHub."
        case .expired: "The code expired. Try again."
        case .busy: "GitHub is busy. Try again in a few minutes."
        case .unavailable: "Sign-in with GitHub isn't available right now."
        case .failed: "Couldn't reach GitHub. Check your connection and try again."
        }
    }

    /// Maps an OAuth `error` value from the device flow (§4.3).
    init(oauthError: String) {
        switch oauthError {
        case "expired_token", "incorrect_device_code": self = .expired
        case "access_denied": self = .denied
        case "slow_down": self = .busy
        case "device_flow_disabled", "incorrect_client_credentials", "unsupported_grant_type", "unauthorized_client":
            self = .unavailable
        default: self = .failed
        }
    }
}

/// Every field github.com's OAuth endpoints answer with (§4.3). All optional: which ones arrive depends on the call
/// and the outcome.
struct OAuthAnswer: Decodable {
    var deviceCode: String?
    var userCode: String?
    var verificationURI: String?
    var expiresIn: Double?
    var interval: Double?
    var accessToken: String?
    var refreshToken: String?
    var refreshTokenExpiresIn: Double?
    var error: String?

    private enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case refreshTokenExpiresIn = "refresh_token_expires_in"
        case error
    }

    static func decode(_ data: Data) -> OAuthAnswer? {
        try? JSONDecoder().decode(OAuthAnswer.self, from: data)
    }

    /// The pair in a token answer, or nil when it has no access token. A token without an expiry (a GitHub App with
    /// expiring tokens turned off) never needs a refresh; without a refresh token, the next 401 ends the sign-in.
    func tokenPair(now: Date) -> TokenPair? {
        guard let accessToken, !accessToken.isEmpty else { return nil }
        return TokenPair(
            access: accessToken,
            refresh: refreshToken ?? "",
            accessExpiresAt: expiresIn.map { now.addingTimeInterval($0) } ?? .distantFuture,
            refreshExpiresAt: refreshTokenExpiresIn.map { now.addingTimeInterval($0) } ?? .distantFuture
        )
    }
}
