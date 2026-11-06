import Foundation
import HeadroomModel
import Testing
@testable import CopilotKit

/// Tokens never appear in URLs, descriptions, errors or logs; every request names the app (1.1 §4.3, §11.1).
@Suite struct TokenSafetyTests {
    private let now = midSeptember
    private let secrets = [
        "ghu_EXAMPLEaccess0001", "ghr_EXAMPLErefresh0001", "ghu_EXAMPLEaccess0002", "ghr_EXAMPLErefresh0002",
        "3584d83530557fdd1f46af8289938c8ef79f9dc5",
    ]

    private func expectNoSecrets(in text: String, sourceLocation: SourceLocation = #_sourceLocation) {
        for secret in secrets {
            #expect(!text.contains(secret), "leaked \(secret.prefix(4))…", sourceLocation: sourceLocation)
        }
    }

    private func everyDescription(of value: Any) -> String {
        var dumped = ""
        dump(value, to: &dumped)
        var texts = [String(describing: value), String(reflecting: value), dumped]
        if let error = value as? any Error { texts.append(error.localizedDescription) }
        return texts.joined(separator: "\n")
    }

    /// Sign-in, login, a refresh after a 401 and a usage poll: no secret in any URL, and every request carries
    /// `User-Agent: Headroom/<version> (macOS)`.
    @Test func aWholeSessionKeepsTokensOutOfURLs() async throws {
        let http = HTTPStub([
            .json(try fixture("device_code")), .json(try fixture("token")), .json(try fixture("user")),
            .http(401, ""), .json(try fixture("token_rotated")), .json(try fixture("usage_empty")),
            .json(try fixture("usage_premium_requests")),
        ])
        let flow = DeviceFlow(
            clientID: "Iv23liEXAMPLE", transport: http.transport, userAgent: http.userAgent, clock: { midSeptember },
            sleep: { _ in }
        )
        let client = UsageClient(transport: http.transport, userAgent: http.userAgent)
        let store = MemoryTokenStore(nil)
        let refresher = TokenRefresher(refresher: flow, store: store)

        let code = try await flow.requestCode(now: now)
        try await refresher.signIn(with: try await flow.waitForToken(code))
        let login = try await refresher.authorized(now: now) { try await client.currentLogin(accessToken: $0, now: now) }
        let usage = try await refresher.authorized(now: now) {
            try await client.usage(login: login, accessToken: $0, plan: .notSure, customAllowance: nil, now: now)
        }
        #expect(usage.status == .ok)
        #expect(http.requests.count == 7)

        for request in http.requests {
            expectNoSecrets(in: request.url.absoluteString)
            #expect(request.header("User-Agent") == http.userAgent)
            #expect(request.header("User-Agent")?.wholeMatch(of: /Headroom\/[^ ]+ \(macOS\)/) != nil)
        }
        expectNoSecrets(in: everyDescription(of: usage))
        expectNoSecrets(in: everyDescription(of: code))
        expectNoSecrets(in: everyDescription(of: try #require(await store.pair)))
        expectNoSecrets(in: everyDescription(of: flow))
        expectNoSecrets(in: everyDescription(of: client))
    }

    /// Every error a caller can get, described every way: no token, device code or response text.
    @Test func errorsNeverCarryTokens() async throws {
        let pair = TokenPair(
            access: "ghu_EXAMPLEaccess0001", refresh: "ghr_EXAMPLErefresh0001",
            accessExpiresAt: now.addingTimeInterval(60), refreshExpiresAt: now.addingTimeInterval(86_400)
        )
        let echo = #"{"error":"bad_refresh_token","error_description":"ghr_EXAMPLErefresh0001 is not valid"}"#
        let http = HTTPStub([
            .json(echo), .http(429, ""), .http(401, #"{"message":"ghu_EXAMPLEaccess0001"}"#),
            .http(403, "", headers: ["Retry-After": "60"]), .networkError, .http(418, "ghu_EXAMPLEaccess0001"),
            .json(#"{"error":"access_denied","error_description":"ghu_EXAMPLEaccess0001"}"#),
        ])
        let flow = DeviceFlow(
            clientID: "Iv23liEXAMPLE", transport: http.transport, userAgent: http.userAgent, clock: { midSeptember },
            sleep: { _ in }
        )
        let client = UsageClient(transport: http.transport, userAgent: http.userAgent)
        let code = DeviceCode(
            deviceCode: "3584d83530557fdd1f46af8289938c8ef79f9dc5", userCode: "WDJB-MJHT",
            verificationURI: try #require(URL(string: "https://github.com/login/device")),
            expiresAt: now.addingTimeInterval(900), interval: 5
        )

        var errors: [any Error] = []
        for attempt in 0..<7 {
            do {
                switch attempt {
                case 0, 1: _ = try await flow.refresh(pair, now: now)
                case 6: _ = try await flow.waitForToken(code)
                default:
                    _ = try await client.usage(
                        login: "octocat", accessToken: pair.access, plan: .legacyPro, customAllowance: nil, now: now
                    )
                }
                Issue.record("Attempt \(attempt) should fail")
            } catch {
                errors.append(error)
            }
        }
        #expect(errors.count == 7)
        for error in errors {
            expectNoSecrets(in: everyDescription(of: error))
            let status = CopilotUsageMapping.status(for: error)
            expectNoSecrets(in: everyDescription(of: CopilotUsageMapping.afterFailure(
                error, last: nil, login: "octocat", plan: .pro, customAllowance: nil
            )))
            #expect(status != .ok)
        }
    }

    /// CopilotKit never logs or prints, and leaves the Keychain to the app (§4.3).
    @Test func sourcesNeverLogOrTouchTheKeychain() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/CopilotKit")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count >= 5)
        let forbidden = [
            "print(", "debugPrint(", "NSLog(", "os_log(", "Logger(", "import os", "OSLog", "FileHandle.standard",
            "SecItem", "kSecClass", "import Security",
        ]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for word in forbidden {
                #expect(!text.contains(word), "\(file.lastPathComponent) contains \(word)")
            }
        }
    }
}
