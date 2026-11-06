import Foundation
import Testing
@testable import HeadroomModel

/// 1.0 JSON (a synthetic snapshot shaped like 1.0 `headroom-dump` output) decodes with the 1.1 defaults (1.1 §2.2).
@Suite struct SnapshotCompatibilityTests {
    private func dumpDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func snapshotFrom10DecodesAsClaudeOnly() throws {
        let snapshot = try dumpDecoder().decode(HeadroomSnapshot.self, from: fixture("snapshot-1.0"))
        #expect(snapshot.codex == nil)
        #expect(snapshot.copilot == nil)
        #expect(snapshot.claudeTracked)
        #expect(snapshot.trackedTools == [.claude])
        #expect(snapshot.isClaudeOnly)

        #expect(snapshot.plan.weekly?.usedPercent == 89)
        #expect(snapshot.plan.weekly?.resetIsEstimated == true)
        #expect(snapshot.plan.fiveHour?.resetsAt == utc("2026-09-24T15:30:00Z"))
        #expect(snapshot.plan.extraUsagePercent == nil)
        #expect(snapshot.issues == [.desktopUsageUnrecognized])
        #expect(snapshot.terminalBridgeConnected)
        #expect(snapshot.generatedAt == utc("2026-09-24T12:40:00Z"))
    }

    @Test func sessionsFrom10AreClaudeSessionsWithoutBaseline() throws {
        let snapshot = try dumpDecoder().decode(HeadroomSnapshot.self, from: fixture("snapshot-1.0"))
        #expect(snapshot.sessions.map(\.id) == [
            "5f0c2a4e-1b7d-4c3e-9a01-000000000001", "5f0c2a4e-1b7d-4c3e-9a01-000000000002",
        ])
        #expect(snapshot.sessions.allSatisfy { $0.tool == .claude })
        #expect(snapshot.sessions.allSatisfy { $0.desktopSessionID == nil })

        let desktop = snapshot.sessions[0]
        let context = try #require(desktop.context)
        #expect(context.baselineTokens == 0)
        #expect(context.usedTokens == 724_000)
        #expect(context.windowTokens == 1_000_000)
        #expect(!context.windowIsAssumed)
        #expect(desktop.pid == 46250)

        let terminal = snapshot.sessions[1]
        #expect(terminal.context == nil)
        #expect(terminal.startedAt == nil)
        #expect(terminal.origin == .terminal)
        #expect(terminal.transcriptPath?.hasSuffix("000000000002.jsonl") == true)
    }

    @Test func accessStateFrom10HasNoCodexOrCopilot() throws {
        let json = #"{"claudeDirectoryReadable":true,"desktopDirectoryReadable":false,"desktopAppInstalled":true}"#
        let access = try JSONDecoder().decode(AccessState.self, from: Data(json.utf8))
        #expect(access == AccessState(claudeDirectoryReadable: true, desktopDirectoryReadable: false))
        #expect(!access.codexDirectoryReadable && !access.codexInstalled)
        #expect(!access.copilotDirectoryReadable && !access.copilotCLIInstalled)
    }

    @Test func multiToolSnapshotRoundTrips() throws {
        let observed = utc("2026-09-24T12:30:00Z")
        let codex = ToolUsage(
            tool: .codex,
            limits: [
                ToolLimit(window: .weekly, usedPercent: 42, resetsAt: utc("2026-09-30T09:00:00Z"), observedAt: observed),
                ToolLimit(window: .fiveHour, usedPercent: 17, resetsAt: nil, observedAt: observed),
            ],
            hasFiveHourWindow: true,
            otherBuckets: [NamedLimits(id: "codex_other", name: "Other model", limits: [
                ToolLimit(window: .minutes(180), usedPercent: 80, resetsAt: nil, resetSinceReading: true, observedAt: observed),
            ])],
            status: .ok,
            planName: "Plus"
        )
        let copilot = ToolUsage(
            tool: .copilot,
            limits: [ToolLimit(
                window: .monthly, usedPercent: nil, used: 512, extra: 120, unit: .aiCredits,
                resetsAt: utc("2026-10-01T00:00:00Z"), observedAt: observed
            )],
            status: .ok,
            account: "octocat"
        )
        let session = SessionInfo(
            id: "codex:01a0beba-55ec-7ac1-84a7-16d9f0a456e0", name: "website", projectPath: nil, origin: .desktop,
            activity: .working, activitySince: observed, startedAt: nil, pid: nil, transcriptPath: nil,
            context: ContextUsage(
                usedTokens: 150_000, windowTokens: 258_400, model: "gpt-x", windowIsExact: true, observedAt: observed,
                baselineTokens: 12_000
            ),
            tool: .codex
        )
        let snapshot = HeadroomSnapshot(
            plan: .empty, sessions: [session], terminalBridgeConnected: false, issues: [.codexUsageUnrecognized],
            generatedAt: observed, codex: codex, copilot: copilot, claudeTracked: false
        )
        // headroom-dump's dates and the widget file's.
        let strategies: [(JSONEncoder.DateEncodingStrategy, JSONDecoder.DateDecodingStrategy)] = [
            (.iso8601, .iso8601), (.secondsSince1970, .secondsSince1970),
        ]
        for (encoding, decoding) in strategies {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = encoding
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = decoding
            let decoded = try decoder.decode(HeadroomSnapshot.self, from: encoder.encode(snapshot))
            #expect(decoded == snapshot)
        }
        #expect(snapshot.trackedTools == [.codex, .copilot])
        #expect(!snapshot.isClaudeOnly)
    }

    @Test func toolLimitMomentRoundTrips() throws {
        let moments: [Moment] = [
            .toolLimitCrossed(tool: .codex, window: .weekly, percent: 90),
            .toolLimitCrossed(tool: .copilot, window: .monthly, percent: 100),
            .limitCrossed(kind: .fiveHour, percent: 90),
        ]
        let decoded = try JSONDecoder().decode([Moment].self, from: JSONEncoder().encode(moments))
        #expect(decoded == moments)
    }

    /// 1.1 §14.3: the Claude app's own session id round-trips, and JSON without it decodes to nil.
    @Test func desktopSessionIDRoundTrips() throws {
        let session = SessionInfo(
            id: "d-1", name: "Refactor invoice export", projectPath: nil, origin: .desktop, activity: .working,
            activitySince: nil, startedAt: nil, pid: nil, transcriptPath: nil, context: nil,
            desktopSessionID: "local_0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b"
        )
        let decoded = try JSONDecoder().decode(SessionInfo.self, from: JSONEncoder().encode(session))
        #expect(decoded == session)
        var without = session
        without.desktopSessionID = nil
        let json = String(decoding: try JSONEncoder().encode(without), as: UTF8.self)
        #expect(!json.contains("desktopSessionID"))
        #expect(try JSONDecoder().decode(SessionInfo.self, from: Data(json.utf8)).desktopSessionID == nil)
    }
}
