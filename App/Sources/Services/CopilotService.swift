import CopilotKit
import Foundation
import HeadroomModel

/// GitHub Copilot usage (1.1 §4.3–§4.7): the one place that signs in to GitHub, reads, refreshes and deletes the
/// token pair, and asks GitHub for this month's usage. The app has one; `--render-live`, the widget and everything
/// else never touch the tokens. One `UsageClient`, one `TokenRefresher` (refreshing through the `DeviceFlow`), one
/// `CopilotPollPolicy`.
///
/// The service doesn't decide whether Copilot is tracked, or schedule itself: `CopilotAccount` asks it to `poll` for a
/// trigger (the policy may say no) and to say when the timer is due (`nextTimerPoll`).
actor CopilotService {
    /// What one poll found.
    struct PollOutcome: Sendable, Equatable {
        /// `.ok`, `.noIndividualUsage` or `.unrecognized` after an answer; after a failure what
        /// `CopilotUsageMapping.afterFailure` keeps: `.offline` and `.rateLimited` keep the last reading, dimmed;
        /// `.signInExpired`; `.notConnected` when there is no stored pair (the Keychain item is gone).
        var usage: ToolUsage
        /// The login fetched on the way, when none was known yet.
        var fetchedLogin: String?
        /// GitHub answered with usage (or with none billed): "updated 5m ago".
        var succeeded: Bool
    }

    private let deviceFlow: DeviceFlow
    private let refresher: TokenRefresher
    private let client: UsageClient
    private var policy = CopilotPollPolicy()
    /// The connected login, once known (`CopilotAccount` hands over the saved one).
    private var login: String?
    private var plan: CopilotPlan
    private var customAllowance: Double?
    /// The last reading GitHub gave, kept through failures.
    private var lastUsage: ToolUsage?
    /// Bumped on every sign-in and sign-out: a poll that started before one finishes too late to count.
    private var connection = 0

    init(
        deviceFlow: DeviceFlow, store: any TokenStore, client: UsageClient, login: String?, plan: CopilotPlan,
        customAllowance: Double?
    ) {
        self.deviceFlow = deviceFlow
        refresher = TokenRefresher(refresher: deviceFlow, store: store)
        self.client = client
        self.login = login
        self.plan = plan
        self.customAllowance = customAllowance
    }

    /// The app's: Headroom's own GitHub App (`clientID`), its Keychain item and an ephemeral URL session (no cookies,
    /// no cache on disk). Every request says `Headroom/<version> (macOS)`.
    static func live(
        clientID: String, appVersion: String, login: String?, plan: CopilotPlan, customAllowance: Double?
    ) -> CopilotService {
        let transport = URLSessionTransport(session: URLSession(configuration: .ephemeral))
        let userAgent = GitHubAPI.userAgent(appVersion: appVersion)
        return CopilotService(
            deviceFlow: DeviceFlow(clientID: clientID, transport: transport, userAgent: userAgent),
            store: KeychainTokenStore(),
            client: UsageClient(transport: transport, userAgent: userAgent),
            login: login,
            plan: plan,
            customAllowance: customAllowance
        )
    }

    // MARK: Plan (1.1 §4.5)

    /// The Plan picker changed: the last reading with the new allowance, at once, without asking GitHub.
    func setPlan(_ plan: CopilotPlan, customAllowance: Double?) -> ToolUsage? {
        self.plan = plan
        self.customAllowance = customAllowance
        lastUsage = lastUsage.map { CopilotUsageMapping.applying(plan: plan, customAllowance: customAllowance, to: $0) }
        return lastUsage
    }

    // MARK: Polling (1.1 §4.4, §4.7)

    /// When the timer should poll next.
    func nextTimerPoll(now: Date) -> Date {
        policy.nextTimerPoll(now: now)
    }

    /// Asks GitHub for this month's usage when the policy allows it for `trigger`; nil when it didn't poll (or the
    /// poll was cancelled, or a sign-in or sign-out overtook it).
    func poll(_ trigger: CopilotPollPolicy.Trigger, now: Date) async -> PollOutcome? {
        guard policy.shouldPoll(trigger, now: now) else { return nil }
        let started = connection
        let client = client
        var fetchedLogin: String?
        do {
            let login: String
            if let known = self.login {
                login = known
            } else {
                login = try await refresher.authorized(now: now) { try await client.currentLogin(accessToken: $0, now: now) }
                policy.recordRequests(1, at: now)
                guard started == connection else { return nil }
                self.login = login
                fetchedLogin = login
            }
            let (plan, custom) = (self.plan, self.customAllowance)
            let fetchUsage = { @Sendable (login: String, token: String) async throws -> ToolUsage in
                try await client.usage(login: login, accessToken: token, plan: plan, customAllowance: custom, now: now)
            }
            let fetched: ToolUsage
            do {
                fetched = try await refresher.authorized(now: now) { try await fetchUsage(login, $0) }
            } catch UsageClientError.unexpectedResponse(statusCode: 404) where fetchedLogin == nil {
                // GitHub doesn't know the saved login: the account may have been renamed since sign-in. Ask `/user`
                // again, and with a new login try once more.
                let current = try await refresher.authorized(now: now) {
                    try await client.currentLogin(accessToken: $0, now: now)
                }
                policy.recordRequests(2, at: now)
                guard started == connection else { return nil }
                guard current != login else { throw UsageClientError.unexpectedResponse(statusCode: 404) }
                self.login = current
                fetchedLogin = current
                fetched = try await refresher.authorized(now: now) { try await fetchUsage(current, $0) }
            }
            guard started == connection else { return nil }
            policy.recordSuccess(at: now)
            // The Plan picker may have changed while GitHub answered.
            let usage = CopilotUsageMapping.applying(plan: self.plan, customAllowance: customAllowance, to: fetched)
            lastUsage = usage
            return PollOutcome(usage: usage, fetchedLogin: fetchedLogin, succeeded: true)
        } catch is CancellationError {
            return nil
        } catch {
            guard started == connection else { return nil }
            policy.recordFailure(error, at: now)
            let usage = CopilotUsageMapping.afterFailure(
                error, last: lastUsage, login: login, plan: plan, customAllowance: customAllowance
            )
            return PollOutcome(usage: usage, fetchedLogin: fetchedLogin, succeeded: false)
        }
    }

    // MARK: Signing in and out (1.1 §4.3)

    /// The code for the Connect GitHub sheet. Throws `DeviceFlowError`.
    func requestCode(now: Date) async throws -> DeviceCode {
        try await deviceFlow.requestCode(now: now)
    }

    /// Waits until the user approves `code` on GitHub, keeps the new pair in the Keychain and returns the login
    /// ("Connected as @octocat"). Throws `DeviceFlowError`, or `CancellationError` when the sheet is cancelled. When
    /// the login can't be fetched, the new pair is deleted again and the sign-in fails: a sign-in without a login
    /// would leave a token nobody shows.
    func signIn(with code: DeviceCode) async throws -> String {
        let pair = try await deviceFlow.waitForToken(code)
        try Task.checkCancellation()
        connection += 1
        login = nil
        lastUsage = nil
        policy.reset()
        do {
            try await refresher.signIn(with: pair)
            let now = Date()
            let client = client
            let login = try await refresher.authorized(now: now) { try await client.currentLogin(accessToken: $0, now: now) }
            policy.recordRequests(1, at: now)
            self.login = login
            return login
        } catch {
            try? await refresher.signOut()
            if error is CancellationError { throw error }
            throw DeviceFlowError.failed
        }
    }

    /// Disconnect: deletes the Keychain item and forgets the login and the reading. Revoking the grant on GitHub
    /// needs a client secret, which Headroom doesn't have: the user does that on github.com.
    func signOut() async throws {
        connection += 1
        login = nil
        lastUsage = nil
        policy.reset()
        try await refresher.signOut()
    }
}
