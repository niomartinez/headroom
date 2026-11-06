import Foundation
import Testing
@testable import CopilotKit

/// One canned HTTP answer, or a network failure.
enum StubAnswer: Sendable {
    case http(Int, String, headers: [String: String] = [:])
    case networkError

    static func json(_ body: String, headers: [String: String] = [:]) -> StubAnswer { .http(200, body, headers: headers) }
}

/// A request as the stub saw it.
struct SeenRequest: Sendable {
    var method: String
    var url: URL
    var headers: [String: String]
    var body: Data

    var form: [String: String] { FormEncoding.decode(body) }
    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// Stubbed HTTP through `URLProtocol` (§11.1): a real `URLSession` whose requests never leave the process. Each stub
/// answers its queued answers in order. Requests reach their stub by `User-Agent`, which carries a per-stub version,
/// so tests run in parallel.
final class HTTPStub: @unchecked Sendable {
    let id = UUID().uuidString.lowercased()
    private let lock = NSLock()
    private var answers: [StubAnswer]
    private var seen: [SeenRequest] = []

    init(_ answers: [StubAnswer] = []) {
        self.answers = answers
        StubURLProtocol.register(self)
    }

    deinit { StubURLProtocol.unregister(id) }

    /// `Headroom/1.1.0-<id> (macOS)`.
    var userAgent: String { GitHubAPI.userAgent(appVersion: "1.1.0-\(id)") }

    var transport: any HTTPTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionTransport(session: URLSession(configuration: configuration))
    }

    var requests: [SeenRequest] { lock.withLock { seen } }

    func enqueue(_ more: StubAnswer...) { lock.withLock { answers += more } }

    fileprivate func answer(_ request: SeenRequest) -> StubAnswer? {
        lock.withLock {
            seen.append(request)
            return answers.isEmpty ? nil : answers.removeFirst()
        }
    }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [String: HTTPStub] = [:]

    static func register(_ stub: HTTPStub) { lock.withLock { stubs[stub.id] = stub } }
    static func unregister(_ id: String) { _ = lock.withLock { stubs.removeValue(forKey: id) } }

    private static func stub(for request: URLRequest) -> HTTPStub? {
        guard let agent = request.value(forHTTPHeaderField: "User-Agent") else { return nil }
        return lock.withLock { stubs.first { agent.contains($0.key) }?.value }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let seen = SeenRequest(
            method: request.httpMethod ?? "GET", url: request.url!, headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody ?? Self.read(request.httpBodyStream)
        )
        guard let answer = Self.stub(for: request)?.answer(seen) else {
            Issue.record("Unexpected request \(seen.method) \(seen.url)")
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        switch answer {
        case .networkError:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case let .http(status, body, headers):
            let response = HTTPURLResponse(url: seen.url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// A clock that only moves when the device flow sleeps, recording each sleep.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private var slept: [TimeInterval] = []

    init(_ now: Date) { current = now }

    var now: Date { lock.withLock { current } }
    var sleeps: [TimeInterval] { lock.withLock { slept } }

    func sleep(_ seconds: TimeInterval) async throws {
        try Task.checkCancellation()
        lock.withLock {
            slept.append(seconds)
            current = current.addingTimeInterval(seconds)
        }
    }
}

/// The in-memory `TokenStore` (§11.1): records every save, each one a whole pair.
actor MemoryTokenStore: TokenStore {
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

/// A fixture from `Fixtures/copilot`, as text.
func fixture(_ name: String) throws -> String {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/copilot")
    )
    return try String(contentsOf: url, encoding: .utf8)
}

/// 2026-09-15 12:00:00 UTC.
let midSeptember = utc(2026, 9, 15, 12)

/// A date from UTC components.
func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}
