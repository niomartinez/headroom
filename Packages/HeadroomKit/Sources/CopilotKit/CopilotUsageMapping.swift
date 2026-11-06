import Foundation
import HeadroomModel

/// Turns GitHub's billing reports into Copilot's `ToolUsage` (§4.4–§4.6). Pure: the app also uses it to apply a new
/// plan choice to the current reading without a fetch, and to keep the last reading when a poll fails.
public enum CopilotUsageMapping {
    /// A `unitType` as compared (§4.4): lowercased, with `_` and spaces turned into `-`, so `AI_Credits`,
    /// `ai_credits` and `ai-credits` all read `ai-credits`.
    public static func normalizedUnitType(_ unitType: String) -> String {
        unitType.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    /// The usage from one poll's reports, in the order they were asked (§4.4, §4.6): the first report with matching
    /// items → `.ok` with one monthly limit; items in none of the expected units → `.unrecognized` (no number is
    /// guessed); no items at all → `.noIndividualUsage`.
    static func usage(
        reports: [BillingReport], login: String, plan: CopilotPlan, customAllowance: Double?
    ) -> ToolUsage {
        guard let report = reports.first(where: { $0.matchingItems > 0 }) else {
            let status: ToolStatus = reports.contains { $0.itemCount > 0 } ? .unrecognized : .noIndividualUsage
            return ToolUsage(tool: .copilot, status: status, planName: plan.presetName, account: login)
        }
        let limit = ToolLimit(
            window: .monthly,
            usedPercent: nil,
            used: report.used,
            extra: report.extra > 0 ? report.extra : nil,
            unit: report.unit,
            resetsAt: UTCMonth(containing: report.observedAt).nextStart,
            resetIsEstimated: false,
            observedAt: report.observedAt
        )
        return ToolUsage(
            tool: .copilot,
            limits: [Self.limit(limit, applying: plan, customAllowance: customAllowance)],
            hasFiveHourWindow: false,
            status: .ok,
            planName: plan.presetName,
            account: login
        )
    }

    /// An organization-paid seat's monthly quota from `copilot_internal/user`: `.ok` with GitHub's own allowance,
    /// resetting the next 1st at 00:00 UTC. Nil for a personal plan, or an unlimited or missing quota.
    static func seatUsage(_ seat: CopilotSeatBody, login: String, now: Date) -> ToolUsage? {
        let planName: String
        switch seat.copilotPlan {
        case "business": planName = "Business"
        case "enterprise": planName = "Enterprise"
        default: return nil
        }
        guard let quota = seat.quotaSnapshots?.premiumInteractions, quota.unlimited != true,
              let allowance = quota.entitlement, allowance.isFinite, allowance > 0,
              let remaining = quota.remaining, remaining.isFinite
        else { return nil }
        let used = max(0, allowance - remaining)
        let limit = ToolLimit(
            window: .monthly,
            usedPercent: used * 100 / allowance,
            used: used,
            allowance: allowance,
            unit: seat.tokenBasedBilling == false ? .premiumRequests : .aiCredits,
            resetsAt: UTCMonth(containing: now).nextStart,
            observedAt: now
        )
        return ToolUsage(
            tool: .copilot, limits: [limit], status: .ok, planName: planName, account: login, organizationSeat: true
        )
    }

    /// `usage` with the allowance, percent and plan name of `plan` (§4.5), e.g. right after the Plan picker changes.
    /// A preset whose unit differs from the reading's (Pro's credits against premium requests) gives no allowance
    /// and no percent rather than a wrong one. An organization seat's reading keeps GitHub's allowance.
    public static func applying(plan: CopilotPlan, customAllowance: Double?, to usage: ToolUsage) -> ToolUsage {
        guard usage.tool == .copilot, usage.organizationSeat != true else { return usage }
        var usage = usage
        usage.planName = plan.presetName
        usage.limits = usage.limits.map { limit($0, applying: plan, customAllowance: customAllowance) }
        return usage
    }

    /// What a failed poll shows (§4.6): `.offline` and `.rateLimited` keep the last reading (dimmed by its age, "as
    /// of 2h ago"); `.signInExpired` and `.notConnected` show none. Cancellations aren't failures: don't pass them.
    public static func afterFailure(
        _ error: any Error, last: ToolUsage?, login: String?, plan: CopilotPlan, customAllowance: Double?
    ) -> ToolUsage {
        let status = status(for: error)
        var usage = ToolUsage(
            tool: .copilot, status: status, planName: plan.presetName, account: login ?? last?.account
        )
        if status == .offline || status == .rateLimited, let last, last.tool == .copilot {
            usage.limits = applying(plan: plan, customAllowance: customAllowance, to: last).limits
            if last.organizationSeat == true {
                usage.planName = last.planName
                usage.organizationSeat = true
            }
        }
        return usage
    }

    /// The Copilot status for an error from `TokenRefresher.authorized` or `UsageClient` (§4.6).
    public static func status(for error: any Error) -> ToolStatus {
        switch error {
        case let error as TokenRefreshError:
            return error.status
        case let error as UsageClientError:
            switch error {
            case .unauthorized: return .signInExpired
            case .rateLimited: return .rateLimited
            case .offline: return .offline
            // GitHub answered, but not with usage (a 404, an unreadable body): not "Can't reach GitHub".
            case .unexpectedResponse(let code): return (500..<600).contains(code) ? .offline : .unrecognized
            }
        default:
            return .offline
        }
    }

    private static func limit(_ limit: ToolLimit, applying plan: CopilotPlan, customAllowance: Double?) -> ToolLimit {
        guard let unit = limit.unit else { return limit }
        var limit = limit
        let allowance = plan.unit == nil || plan.unit == unit ? plan.allowance(custom: customAllowance) : nil
        limit.allowance = allowance
        limit.usedPercent = allowance.flatMap { allowance in limit.used.map { $0 * 100 / allowance } }
        return limit
    }
}

/// One billing endpoint's answer, summed (§4.4): `used` = Σ grossQuantity and `extra` = Σ netQuantity (billed beyond
/// the included amount) over the items in the endpoint's unit.
struct BillingReport: Sendable, Equatable {
    var unit: UsageUnit
    var itemCount: Int
    var matchingItems: Int
    var used: Double
    var extra: Double
    /// The fetch time.
    var observedAt: Date

    init(endpoint: UsageUnitEndpoint, items: [BillingUsageItem], observedAt: Date) {
        let expected: String
        switch endpoint {
        case .aiCredit:
            unit = .aiCredits
            expected = "ai-credits"
        case .premiumRequest:
            unit = .premiumRequests
            expected = "requests"
        }
        let matching = items.filter { $0.unitType.map(CopilotUsageMapping.normalizedUnitType) == expected }
        itemCount = items.count
        matchingItems = matching.count
        used = matching.reduce(0) { $0 + Self.finite($1.grossQuantity) }
        extra = matching.reduce(0) { $0 + Self.finite($1.netQuantity) }
        self.observedAt = observedAt
    }

    private static func finite(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return value
    }
}
