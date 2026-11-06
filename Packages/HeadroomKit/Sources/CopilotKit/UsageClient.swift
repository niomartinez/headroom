import Foundation
import HeadroomModel

/// Fetches the signed-in login and this month's Copilot usage from GitHub's API (§4.3, §4.4) and maps the usage to
/// a `ToolUsage`. Run each call through `TokenRefresher.authorized`.
///
/// It remembers the last `premium_request` check (§4.4: at most once an hour on a credits plan), so keep one client
/// for the app's lifetime; copies share that memory.
public struct UsageClient: Sendable {
    private let transport: any HTTPTransport
    private let userAgent: String
    private let premiumChecks = PremiumRequestChecks()

    /// How long a `premium_request` check stands while `ai_credit` has no items (§4.4).
    public static let premiumRecheckInterval: TimeInterval = 60 * 60

    public init(transport: any HTTPTransport, userAgent: String) {
        self.transport = transport
        self.userAgent = userAgent
    }

    /// `GET https://api.github.com/user` → the login (`octocat`), fetched right after sign-in: "Connected as @octocat",
    /// kept in `copilotLogin` and passed to `usage(login:…)`. Throws `UsageClientError`.
    public func currentLogin(accessToken: String, now: Date = Date()) async throws -> String {
        let data = try await get(GitHubEndpoint.user, accessToken: accessToken, now: now)
        guard let user = try? JSONDecoder().decode(GitHubUser.self, from: data), GitHubLogin.isValid(user.login)
        else { throw UsageClientError.unexpectedResponse(statusCode: 200) }
        return user.login
    }

    /// `GET /users/{login}/settings/billing/ai_credit/usage?year=&month=` for the UTC month of `now` (and
    /// `premium_request/usage` for legacy plans, or at most once an hour when the credits endpoint has no items),
    /// mapped per §4.4 by `CopilotUsageMapping`: one monthly `ToolLimit` resetting the next 1st at 00:00 UTC, `.ok`,
    /// `.noIndividualUsage` or `.unrecognized`, `account` = `login`, stale after 45 min. Throws `UsageClientError`
    /// for the states that keep the last reading (`CopilotUsageMapping.afterFailure`).
    ///
    /// With nothing billed to the user, an organization may pay for the seat: `seatUsage` then asks for its quota.
    ///
    /// A poll makes at most `CopilotPollPolicy.requestsPerPoll` requests.
    public func usage(
        login: String, accessToken: String, plan: CopilotPlan, customAllowance: Double?, now: Date
    ) async throws -> ToolUsage {
        guard GitHubLogin.isValid(login) else { throw UsageClientError.unexpectedResponse(statusCode: 0) }
        let month = UTCMonth(containing: now)
        var reports: [BillingReport] = []
        if plan.isLegacy {
            reports.append(try await report(.premiumRequest, login: login, month: month, accessToken: accessToken, now: now))
        } else {
            let credits = try await report(.aiCredit, login: login, month: month, accessToken: accessToken, now: now)
            reports.append(credits)
            if credits.matchingItems == 0 {
                if let recent = await premiumChecks.recent(login: login, month: month, now: now) {
                    reports.append(recent)
                } else {
                    let premium = try await report(
                        .premiumRequest, login: login, month: month, accessToken: accessToken, now: now
                    )
                    await premiumChecks.remember(premium, login: login, month: month)
                    reports.append(premium)
                }
            }
        }
        let usage = CopilotUsageMapping.usage(reports: reports, login: login, plan: plan, customAllowance: customAllowance)
        guard usage.status == .noIndividualUsage else { return usage }
        return try await seatUsage(login: login, accessToken: accessToken, now: now) ?? usage
    }

    /// `GET /copilot_internal/user` (undocumented; Nio, 2026-10-02): an organization-paid seat's quota, which the
    /// billing endpoints never show. Nil when GitHub refuses or answers anything else, so a failure here never
    /// changes the documented answer, nor asks for a new sign-in.
    private func seatUsage(login: String, accessToken: String, now: Date) async throws -> ToolUsage? {
        let data: Data
        do {
            data = try await get(GitHubEndpoint.copilotSeat, accessToken: accessToken, now: now)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let seat = try? decoder.decode(CopilotSeatBody.self, from: data) else { return nil }
        return CopilotUsageMapping.seatUsage(seat, login: login, now: now)
    }

    private func report(
        _ endpoint: UsageUnitEndpoint, login: String, month: UTCMonth, accessToken: String, now: Date
    ) async throws -> BillingReport {
        let url = GitHubEndpoint.billingUsage(login: login, unit: endpoint, month: month)
        let data = try await get(url, accessToken: accessToken, now: now)
        guard let body = try? JSONDecoder().decode(BillingUsageBody.self, from: data) else {
            throw UsageClientError.unexpectedResponse(statusCode: 200)
        }
        return BillingReport(endpoint: endpoint, items: body.usageItems, observedAt: now)
    }

    private func get(_ url: URL, accessToken: String, now: Date) async throws -> Data {
        let request = URLRequest.gitHubAPI(url, accessToken: accessToken, userAgent: userAgent)
        let (data, response) = try await send(request, with: transport, failure: UsageClientError.offline)
        switch response.statusCode {
        case 200: return data
        case 401: throw UsageClientError.unauthorized
        case 403, 429: throw UsageClientError.rateLimited(retryAfter: RateLimitHeaders.retryAfter(response, now: now))
        case 500..<600: throw UsageClientError.offline
        default: throw UsageClientError.unexpectedResponse(statusCode: response.statusCode)
        }
    }
}

/// The last `premium_request` check, per login and UTC month (§4.4).
actor PremiumRequestChecks {
    private var last: (login: String, month: UTCMonth, report: BillingReport)?

    /// The check made less than `UsageClient.premiumRecheckInterval` ago, if any.
    func recent(login: String, month: UTCMonth, now: Date) -> BillingReport? {
        guard let last, last.login == login, last.month == month else { return nil }
        let age = now.timeIntervalSince(last.report.observedAt)
        return (0..<UsageClient.premiumRecheckInterval).contains(age) ? last.report : nil
    }

    func remember(_ report: BillingReport, login: String, month: UTCMonth) {
        last = (login, month, report)
    }
}

/// `GET /user`'s one field Headroom reads.
private struct GitHubUser: Decodable {
    var login: String
}

/// A billing usage report (§4.4): `{"timePeriod":{…},"user":"octocat","usageItems":[…]}`. Only `usageItems` is read.
struct BillingUsageBody: Decodable {
    var usageItems: [BillingUsageItem]
}

/// `GET /copilot_internal/user`'s fields Headroom reads, decoded from snake case: `{"copilot_plan":"enterprise",
/// "token_based_billing":true,"quota_snapshots":{"premium_interactions":{"entitlement":50000,"remaining":49180,
/// "unlimited":false,…},…},…}`.
struct CopilotSeatBody: Decodable {
    var copilotPlan: String?
    var tokenBasedBilling: Bool?
    var quotaSnapshots: QuotaSnapshots?

    struct QuotaSnapshots: Decodable {
        var premiumInteractions: Quota?
    }

    struct Quota: Decodable {
        var entitlement: Double?
        var remaining: Double?
        var unlimited: Bool?
    }
}

/// One usage item. Only the unit and the quantities are read; `product`, `sku` and `model` may be missing
/// [V-gh OpenAPI].
struct BillingUsageItem: Decodable, Sendable, Equatable {
    var unitType: String?
    var grossQuantity: Double?
    var netQuantity: Double?
}
