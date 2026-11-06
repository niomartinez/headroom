import Foundation

/// GitHub's endpoints (§4.3, §4.4).
enum GitHubEndpoint {
    static let deviceCode = URL(string: "https://github.com/login/device/code")!
    static let accessToken = URL(string: "https://github.com/login/oauth/access_token")!
    static let user = URL(string: "https://api.github.com/user")!
    /// Undocumented: the signed-in user's Copilot seat and its quotas. Asked only when nothing is billed to the user.
    static let copilotSeat = URL(string: "https://api.github.com/copilot_internal/user")!
    /// The REST API version every API request pins (§4.4).
    static let apiVersion = "2026-03-10"

    /// `GET /users/{login}/settings/billing/{ai_credit|premium_request}/usage?year=&month=`.
    static func billingUsage(login: String, unit: UsageUnitEndpoint, month: UTCMonth) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/users/\(login)/settings/billing/\(unit.rawValue)/usage"
        components.queryItems = [
            URLQueryItem(name: "year", value: String(month.year)),
            URLQueryItem(name: "month", value: String(month.month)),
        ]
        return components.url!
    }
}

/// The two billing endpoints (§4.4): current plans count AI credits, yearly plans on the older billing count
/// premium requests.
enum UsageUnitEndpoint: String, Sendable {
    case aiCredit = "ai_credit"
    case premiumRequest = "premium_request"
}

/// A GitHub login as `/user` returns it: letters, digits, `-` and `_` (managed users' `octocat_acme`). Anything else
/// is refused rather than put in a URL path.
enum GitHubLogin {
    static func isValid(_ login: String) -> Bool {
        !login.isEmpty && login.count <= 100
            && login.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") }
    }
}

extension URLRequest {
    /// A form POST to github.com's OAuth endpoints. The parameters go in the body, never in the URL, so no token or
    /// device code ends up in a URL (§4.3). GitHub answers JSON because of `Accept`.
    static func gitHubOAuthForm(_ url: URL, _ parameters: [(String, String)], userAgent: String) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = FormEncoding.encode(parameters)
        return request
    }

    /// A GET against GitHub's REST API with the access token in the `Authorization` header (§4.4).
    static func gitHubAPI(_ url: URL, accessToken: String, userAgent: String) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(GitHubEndpoint.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }
}

/// `application/x-www-form-urlencoded`, encoding everything but RFC 3986's unreserved characters.
enum FormEncoding {
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    static func encode(_ parameters: [(String, String)]) -> Data {
        let pairs = parameters.map { name, value in "\(escape(name))=\(escape(value))" }
        return Data(pairs.joined(separator: "&").utf8)
    }

    static func decode(_ data: Data) -> [String: String] {
        var result: [String: String] = [:]
        for pair in String(decoding: data, as: UTF8.self).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = parts.first?.removingPercentEncoding else { continue }
            result[name] = parts.count > 1 ? parts[1].removingPercentEncoding ?? "" : ""
        }
        return result
    }

    private static func escape(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}

/// How long a 403/429 asks to wait (§4.7): `Retry-After` (seconds or an HTTP date), else `x-ratelimit-reset` (epoch
/// seconds), at most `maximumWait`. Nil when neither header is usable.
enum RateLimitHeaders {
    /// GitHub's own waits are seconds to an hour; a longer one is not believed, and a huge one would overflow the
    /// app's timer (`Duration.seconds` traps).
    static let maximumWait: TimeInterval = 24 * 60 * 60

    static func retryAfter(_ response: HTTPURLResponse, now: Date) -> TimeInterval? {
        wait(response, now: now).map { min($0, maximumWait) }
    }

    private static func wait(_ response: HTTPURLResponse, now: Date) -> TimeInterval? {
        if let value = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces) {
            if let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 { return seconds }
            if let date = httpDate(value) { return max(0, date.timeIntervalSince(now)) }
        }
        if let value = response.value(forHTTPHeaderField: "x-ratelimit-reset"),
            let epoch = TimeInterval(value.trimmingCharacters(in: .whitespaces)), epoch.isFinite, epoch > 0
        {
            return max(0, Date(timeIntervalSince1970: epoch).timeIntervalSince(now))
        }
        return nil
    }

    /// RFC 9110's IMF-fixdate, `Sun, 06 Nov 1994 08:49:37 GMT`.
    private static func httpDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: text)
    }
}

/// The UTC calendar month GitHub's billing reports use (§4.4).
struct UTCMonth: Sendable, Equatable {
    var year: Int
    var month: Int

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    init(containing date: Date) {
        let components = Self.calendar.dateComponents([.year, .month], from: date)
        year = components.year!
        month = components.month!
    }

    /// The next month's 1st at 00:00:00 UTC: when this month's usage resets (§4.4).
    var nextStart: Date {
        let start = Self.calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        return Self.calendar.date(byAdding: .month, value: 1, to: start)!
    }
}

/// Sends `request`, rethrowing a cancellation as `CancellationError` and turning any other transport failure into
/// `failure`: an error from the network layer can quote the request, so it never leaves CopilotKit.
func send(
    _ request: URLRequest, with transport: any HTTPTransport, failure: some Error
) async throws -> (Data, HTTPURLResponse) {
    do {
        return try await transport.data(for: request)
    } catch is CancellationError {
        throw CancellationError()
    } catch {
        if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
        throw failure
    }
}
