import Foundation
import Testing
@testable import CopilotKit

/// Sign-in with the device flow (1.1 §4.3, §6.4 sheet errors), HTTP stubbed with `URLProtocol`.
@Suite struct DeviceFlowTests {
    private let start = utc(2026, 9, 15, 12)

    private func flow(_ http: HTTPStub, clock: FakeClock) -> DeviceFlow {
        DeviceFlow(
            clientID: "Iv23liEXAMPLE", transport: http.transport, userAgent: http.userAgent, clock: { clock.now },
            sleep: { try await clock.sleep($0) }
        )
    }

    private func code(expiresIn: TimeInterval = 900, interval: TimeInterval = 5) throws -> DeviceCode {
        DeviceCode(
            deviceCode: "3584d8EXAMPLE", userCode: "WDJB-MJHT",
            verificationURI: try #require(URL(string: "https://github.com/login/device")),
            expiresAt: start.addingTimeInterval(expiresIn), interval: interval
        )
    }

    private func pending() -> StubAnswer { .json(#"{"error":"authorization_pending"}"#) }

    // MARK: Requesting a code

    @Test func requestCodePostsTheClientIDInTheBody() async throws {
        let http = HTTPStub([.json(try fixture("device_code"))])
        let code = try await flow(http, clock: FakeClock(start)).requestCode(now: start)
        #expect(code.userCode == "WDJB-MJHT")
        #expect(code.deviceCode == "3584d83530557fdd1f46af8289938c8ef79f9dc5")
        #expect(code.verificationURI.absoluteString == "https://github.com/login/device")
        #expect(code.expiresAt == start.addingTimeInterval(900))
        #expect(code.interval == 5)
        let request = try #require(http.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://github.com/login/device/code")
        #expect(request.form == ["client_id": "Iv23liEXAMPLE"])
        #expect(request.header("Accept") == "application/json")
        #expect(request.header("Content-Type") == "application/x-www-form-urlencoded")
    }

    @Test(arguments: [
        (StubAnswer.http(429, ""), DeviceFlowError.busy),
        (.json(#"{"error":"slow_down"}"#), .busy),
        (.http(400, #"{"error":"device_flow_disabled","error_description":"Device Flow must be explicitly enabled"}"#),
         .unavailable),
        (.json(#"{"error":"incorrect_client_credentials"}"#), .unavailable),
        (.http(404, #"{"error":"Not Found"}"#), .unavailable),
        (.http(404, "Not Found"), .unavailable),
        (.http(503, ""), .failed),
        (.json(#"{"user_code":"WDJB-MJHT"}"#), .failed),
        (.json(#"{"device_code":"d","user_code":"U","verification_uri":"http://github.com/login/device","expires_in":900}"#),
         .failed),
        (.networkError, .failed),
    ])
    func requestCodeErrors(answer: StubAnswer, expected: DeviceFlowError) async throws {
        let http = HTTPStub([answer])
        await #expect(throws: expected) {
            try await flow(http, clock: FakeClock(start)).requestCode(now: start)
        }
    }

    // MARK: Polling

    @Test func pollsAtTheIntervalUntilApproved() async throws {
        let http = HTTPStub([pending(), pending(), .json(try fixture("token"))])
        let clock = FakeClock(start)
        let pair = try await flow(http, clock: clock).waitForToken(try code())
        #expect(clock.sleeps == [5, 5, 5])
        #expect(pair.access == "ghu_EXAMPLEaccess0001")
        #expect(pair.refresh == "ghr_EXAMPLErefresh0001")
        #expect(pair.accessExpiresAt == start.addingTimeInterval(15 + 28_800))
        #expect(pair.refreshExpiresAt == start.addingTimeInterval(15 + 15_897_600))
        #expect(http.requests.count == 3)
        for request in http.requests {
            #expect(request.method == "POST")
            #expect(request.url.absoluteString == "https://github.com/login/oauth/access_token")
            #expect(request.form == [
                "client_id": "Iv23liEXAMPLE", "device_code": "3584d8EXAMPLE",
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
        }
    }

    @Test func slowDownAddsFiveSeconds() async throws {
        let http = HTTPStub([
            pending(), .json(#"{"error":"slow_down"}"#), pending(), .json(#"{"error":"slow_down","interval":20}"#),
            .json(try fixture("token")),
        ])
        let clock = FakeClock(start)
        _ = try await flow(http, clock: clock).waitForToken(try code())
        // 5, then +5 on the first slow_down, then GitHub's own 20 (more than 10 + 5).
        #expect(clock.sleeps == [5, 5, 10, 10, 20])
    }

    /// A huge interval from GitHub can't overflow the sleep (`Duration.seconds` traps): 60 s at most.
    @Test func hugeIntervalsAreCapped() async throws {
        let answer = #"{"device_code":"d","user_code":"U","verification_uri":"https://github.com/login/device","expires_in":900,"interval":1e22}"#
        let requested = try await flow(HTTPStub([.json(answer)]), clock: FakeClock(start)).requestCode(now: start)
        #expect(requested.interval == 60)

        let http = HTTPStub([.json(#"{"error":"slow_down","interval":1e22}"#), .json(try fixture("token"))])
        let clock = FakeClock(start)
        _ = try await flow(http, clock: clock).waitForToken(try code())
        #expect(clock.sleeps == [5, 60])
        #expect(DeviceFlow.interval(0) == 1)
        #expect(DeviceFlow.interval(.infinity) == 60)
    }

    @Test func aSlowDownStormIsBusy() async throws {
        let slowDown = StubAnswer.json(#"{"error":"slow_down"}"#)
        let http = HTTPStub([slowDown, slowDown, slowDown, slowDown])
        await #expect(throws: DeviceFlowError.busy) {
            try await flow(http, clock: FakeClock(start)).waitForToken(try code())
        }
        #expect(http.requests.count == 4)
    }

    @Test func givesUpWhenTheCodeExpires() async throws {
        let http = HTTPStub([pending(), pending()])
        let clock = FakeClock(start)
        await #expect(throws: DeviceFlowError.expired) {
            try await flow(http, clock: clock).waitForToken(try code(expiresIn: 12))
        }
        // The third poll would come after the code's expiry: it isn't sent.
        #expect(http.requests.count == 2)
        #expect(clock.sleeps == [5, 5, 5])
    }

    @Test(arguments: [
        (StubAnswer.json(#"{"error":"expired_token"}"#), DeviceFlowError.expired),
        (.json(#"{"error":"incorrect_device_code"}"#), .expired),
        (.json(#"{"error":"access_denied"}"#), .denied),
        (.json(#"{"error":"device_flow_disabled"}"#), .unavailable),
        (.http(401, #"{"error":"incorrect_client_credentials"}"#), .unavailable),
        (.json(#"{"error":"unsupported_grant_type"}"#), .unavailable),
        (.http(429, "", headers: ["Retry-After": "60"]), .busy),
        (.json(#"{"error":"something_new"}"#), .failed),
        (.json(#"{"token_type":"bearer"}"#), .failed),
    ])
    func pollErrors(answer: StubAnswer, expected: DeviceFlowError) async throws {
        let http = HTTPStub([pending(), answer])
        await #expect(throws: expected) {
            try await flow(http, clock: FakeClock(start)).waitForToken(try code())
        }
        #expect(http.requests.count == 2)
    }

    @Test func rideOutABriefNetworkBlip() async throws {
        let http = HTTPStub([.networkError, .http(502, ""), pending(), .json(try fixture("token"))])
        let pair = try await flow(http, clock: FakeClock(start)).waitForToken(try code())
        #expect(pair.access == "ghu_EXAMPLEaccess0001")
    }

    @Test func aLastingNetworkFailureFails() async throws {
        let http = HTTPStub([.networkError, .networkError, .networkError])
        await #expect(throws: DeviceFlowError.failed) {
            try await flow(http, clock: FakeClock(start)).waitForToken(try code())
        }
        #expect(http.requests.count == 3)
    }

    @Test func cancellingStopsPolling() async throws {
        let http = HTTPStub()
        let deviceFlow = DeviceFlow(
            clientID: "Iv23liEXAMPLE", transport: http.transport, userAgent: http.userAgent, clock: { Date() },
            sleep: { try await Task.sleep(for: .seconds($0 * 60)) }
        )
        let deviceCode = try code()
        let task = Task { try await deviceFlow.waitForToken(deviceCode) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(http.requests.isEmpty)
    }

    /// A GitHub App with expiring tokens turned off answers only `access_token`: it never needs a refresh.
    @Test func aTokenWithoutExpiry() async throws {
        let http = HTTPStub([.json(#"{"access_token":"ghu_EXAMPLE","token_type":"bearer","scope":""}"#)])
        let pair = try await flow(http, clock: FakeClock(start)).waitForToken(try code())
        #expect(pair.access == "ghu_EXAMPLE")
        #expect(!pair.accessNeedsRefresh(now: start.addingTimeInterval(365 * 86_400)))
    }

    /// §6.4's sheet copy.
    @Test func sheetMessages() {
        #expect(DeviceFlowError.denied.message == "You declined on GitHub.")
        #expect(DeviceFlowError.expired.message == "The code expired. Try again.")
        #expect(DeviceFlowError.busy.message == "GitHub is busy. Try again in a few minutes.")
        #expect(DeviceFlowError.unavailable.message == "Sign-in with GitHub isn't available right now.")
        #expect(!DeviceFlowError.failed.message.isEmpty)
    }
}

/// Refreshing a pair (1.1 §4.3): both tokens rotate; no client secret.
@Suite struct DeviceFlowRefreshTests {
    private let now = utc(2026, 9, 15, 12)

    private func pair(refreshExpiresIn: TimeInterval = 86_400) -> TokenPair {
        TokenPair(
            access: "ghu_EXAMPLEaccess0001", refresh: "ghr_EXAMPLErefresh0001",
            accessExpiresAt: now.addingTimeInterval(60), refreshExpiresAt: now.addingTimeInterval(refreshExpiresIn)
        )
    }

    private func flow(_ http: HTTPStub) -> DeviceFlow {
        DeviceFlow(clientID: "Iv23liEXAMPLE", transport: http.transport, userAgent: http.userAgent)
    }

    @Test func rotatesBothTokens() async throws {
        let http = HTTPStub([.json(try fixture("token_rotated"))])
        let rotated = try await flow(http).refresh(pair(), now: now)
        #expect(rotated == TokenPair(
            access: "ghu_EXAMPLEaccess0002", refresh: "ghr_EXAMPLErefresh0002",
            accessExpiresAt: now.addingTimeInterval(28_800), refreshExpiresAt: now.addingTimeInterval(15_897_600)
        ))
        let request = try #require(http.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://github.com/login/oauth/access_token")
        #expect(request.form == [
            "client_id": "Iv23liEXAMPLE", "grant_type": "refresh_token", "refresh_token": "ghr_EXAMPLErefresh0001",
        ])
        #expect(request.form["client_secret"] == nil)
    }

    @Test func badRefreshTokenIsRejected() async throws {
        let http = HTTPStub([.json(
            #"{"error":"bad_refresh_token","error_description":"The refresh token passed is incorrect or expired."}"#
        )])
        await #expect(throws: TokenRefreshError.rejected) { try await flow(http).refresh(pair(), now: now) }
    }

    @Test func anExpiredRefreshTokenIsRejectedWithoutARequest() async throws {
        let http = HTTPStub()
        await #expect(throws: TokenRefreshError.rejected) {
            try await flow(http).refresh(pair(refreshExpiresIn: -1), now: now)
        }
        #expect(http.requests.isEmpty)
    }

    @Test(arguments: [
        (StubAnswer.http(429, "", headers: ["Retry-After": "120"]), TokenRefreshError.rateLimited(retryAfter: 120)),
        (.http(403, "", headers: ["x-ratelimit-reset": "1789474500"]), .rateLimited(retryAfter: 900)),
        (.http(403, ""), .rateLimited(retryAfter: nil)),
        (.http(429, "", headers: ["Retry-After": "1e22"]), .rateLimited(retryAfter: 86_400)),
        (.http(502, "Bad gateway"), .offline),
        (.json("not json"), .offline),
        (.networkError, .offline),
    ])
    func failuresKeepThePair(answer: StubAnswer, expected: TokenRefreshError) async throws {
        let http = HTTPStub([answer])
        await #expect(throws: expected) { try await flow(http).refresh(pair(), now: now) }
    }
}
