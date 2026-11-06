import Foundation
import HeadroomModel
import Testing
@testable import CodexKit

/// File names, ids, timestamps and every `rate_limits` variant (1.1 §3.2, §3.4).
@Suite struct RolloutDecodingTests {
    // MARK: - Names and ids

    @Test func rolloutNamesMatchTheRegex() {
        let id = "01a0beba-55ec-7ac1-84a7-16d9f0a456e0"
        let rollout = "01a0bebb-0000-7000-8000-000000000001"
        #expect(RolloutFileName("rollout-2026-09-20T12-11-17-\(id).jsonl")?.threadID == id)
        #expect(RolloutFileName("rollout-2026-09-20T12-11-17-\(id)_\(rollout).jsonl")?.threadID == id)
        #expect(RolloutFileName("rollout-2026-09-20T12-11-17-\(id).jsonl.zst") == nil)
        #expect(RolloutFileName("rollout-2026-09-20T12-11-17-\(id)_.jsonl") == nil)
        #expect(RolloutFileName("rollout-2026-09-20T12-11-17-\(id.uppercased()).jsonl") == nil)
        #expect(RolloutFileName("rollout-2026-09-20-\(id).jsonl") == nil)
        #expect(RolloutFileName("session-2026-09-20T12-11-17-\(id).jsonl") == nil)
        #expect(RolloutFileName("rollout-2026-09-20T12-11-17-\(id).json") == nil)
    }

    @Test func threadIDsAreUUIDv7Times() {
        // 0x01a0beba55ec ms.
        #expect(ThreadID.creationDate("01a0beba-55ec-7ac1-84a7-16d9f0a456e0") == Date(timeIntervalSince1970: 1_789_906_277.868))
        #expect(ThreadID.creationDate("not-a-uuid") == nil)
        let created = date("2026-09-23T23:59:59.500Z")
        #expect(ThreadID.creationDate(RolloutText.threadID(created: created, salt: 7)) == created)
    }

    @Test func lockNamesGiveThreadIDs() {
        #expect(ThreadID.fromLockName("01A0BEBA-55EC-7AC1-84A7-16D9F0A456E0.lock") == "01a0beba-55ec-7ac1-84a7-16d9f0a456e0")
        #expect(ThreadID.fromLockName(".coordination.lock") == nil)
        #expect(ThreadID.fromLockName("01a0beba-55ec-7ac1-84a7-16d9f0a456e0.lck") == nil)
        #expect(ThreadID.fromLockName("junk.lock") == nil)
    }

    @Test func timestampsParseWithAnyFraction() {
        #expect(abs(CodexTime.parse("2026-09-23T13:31:05.698Z")!.timeIntervalSince1970 - 1_790_170_265.698) < 1e-5)
        #expect(abs(CodexTime.parse("2026-09-21T02:18:03.145384Z")!.timeIntervalSince1970 - 1_789_957_083.145384) < 1e-5)
        #expect(CodexTime.parse("2026-09-23T13:31:05Z") == Date(timeIntervalSince1970: 1_790_170_265))
        #expect(CodexTime.parse("2026-09-23T21:31:05+08:00") == Date(timeIntervalSince1970: 1_790_170_265))
        #expect(CodexTime.parse("2026-09-23T13:31:05.Z") == nil)
        #expect(CodexTime.parse("2026-13-23T13:31:05Z") == nil)
        #expect(CodexTime.parse("yesterday") == nil)
        let line = Array(#"{"timestamp":"2026-09-23T13:31:05.698Z","type":"event_msg"}"#.utf8)
        #expect(abs(CodexTime.lineTimestamp(line[...])!.timeIntervalSince1970 - 1_790_170_265.698) < 1e-5)
    }

    // MARK: - rate_limits variants

    private func decode(_ json: String, at time: Date = date("2026-09-23T13:31:05Z")) -> RateLimitDecoding? {
        let line = #"{"timestamp":"2026-09-23T13:31:05Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":\#(json)}}"#
        guard let record = try? JSONDecoder().decode(TailRecord.self, from: Data(line.utf8)) else { return nil }
        switch record.rateLimits {
        case .none: return nil
        case .malformed: return .unrecognized
        case .object(let raw): return CodexLimits.decode(raw, at: time)
        }
    }

    private func windows(_ decoding: RateLimitDecoding?) -> [RateWindow]? {
        guard case .reading(let reading) = decoding else { return nil }
        return reading.windows
    }

    @Test func plusHasFiveHourAndWeekly() {
        let decoding = decode(#"{"limit_id":"codex","primary":{"used_percent":17,"window_minutes":300,"resets_at":1790190000},"secondary":{"used_percent":55.0,"window_minutes":10080,"resets_at":1790700000},"plan_type":"plus"}"#)
        #expect(windows(decoding) == [
            RateWindow(minutes: 300, usedPercent: 17, resetsAt: Date(timeIntervalSince1970: 1_790_190_000)),
            RateWindow(minutes: 10_080, usedPercent: 55, resetsAt: Date(timeIntervalSince1970: 1_790_700_000)),
        ])
    }

    @Test func weeklyInPrimaryIsWeekly() throws {
        guard case .reading(let reading) = decode(#"{"limit_id":"codex","primary":{"used_percent":42.0,"window_minutes":10080,"resets_at":1790700000},"secondary":null,"plan_type":"prolite"}"#) else {
            Issue.record("not decoded")
            return
        }
        let limits = CodexLimits.limits(of: reading)
        #expect(limits.map(\.window) == [.weekly])
        #expect(CodexLimits.usage(from: ["codex": reading]).hasFiveHourWindow == false)
        #expect(CodexLimits.usage(from: ["codex": reading]).planName == "Pro Lite")
    }

    @Test func millisecondResetTimesAreReadDefensively() {
        let decoding = decode(#"{"primary":{"used_percent":1,"window_minutes":300,"resets_at":1790190000000}}"#)
        #expect(windows(decoding)?.first?.resetsAt == Date(timeIntervalSince1970: 1_790_190_000))
    }

    @Test func legacyResetsInSecondsCountFromTheLine() {
        let time = date("2026-09-23T09:01:00Z")
        let decoding = decode(#"{"primary":{"used_percent":12.5,"window_minutes":300,"resets_in_seconds":7200}}"#, at: time)
        #expect(windows(decoding) == [RateWindow(minutes: 300, usedPercent: 12.5, resetsAt: time.addingTimeInterval(7_200))])
    }

    @Test func legacyFlatHasNoResets() {
        let decoding = decode(#"{"primary_used_percent":12.5,"secondary_used_percent":40.0,"primary_window_minutes":300,"secondary_window_minutes":10080}"#)
        #expect(windows(decoding) == [
            RateWindow(minutes: 300, usedPercent: 12.5, resetsAt: nil),
            RateWindow(minutes: 10_080, usedPercent: 40, resetsAt: nil),
        ])
    }

    @Test func missingWindowMinutesUseCodexsFallback() {
        let decoding = decode(#"{"primary":{"used_percent":30},"secondary":{"used_percent":60}}"#)
        #expect(windows(decoding)?.map(\.minutes) == [300, 10_080])
    }

    @Test func missingLimitIDMeansCodex() {
        guard case .reading(let reading) = decode(#"{"primary":{"used_percent":30,"window_minutes":10080}}"#) else {
            Issue.record("not decoded")
            return
        }
        #expect(reading.bucketID == "codex")
    }

    @Test func premiumWithNullWindowsIsAKnownEmptyBucket() {
        guard case .reading(let reading) = decode(#"{"limit_id":"premium","limit_name":null,"primary":null,"secondary":null,"credits":null,"plan_type":"pro"}"#) else {
            Issue.record("not decoded")
            return
        }
        #expect(reading.bucketID == "premium")
        #expect(reading.windows.isEmpty)
        #expect(CodexLimits.usage(from: ["premium": reading]).otherBuckets.isEmpty)
    }

    @Test func unknownShapesAreUnrecognized() {
        #expect(decode("{}") == .unrecognized)
        #expect(decode(#"{"windows":[{"pct":3}]}"#) == .unrecognized)
        #expect(decode(#"{"limit_id":"codex","primary":{"weird":1}}"#) == .unrecognized)
        #expect(decode(#"{"limit_id":"codex","primary":"42%"}"#) == .unrecognized)
        #expect(decode(#"{"primary":{"used_percent":5,"window_minutes":0}}"#) == .unrecognized)
        #expect(decode(#"{"primary":{"used_percent":-5,"window_minutes":300}}"#) == .unrecognized)
        #expect(decode(#""soon""#) == .unrecognized)
        #expect(decode("null") == nil)
    }

    @Test func numbersMayBeStringsOrWhole() {
        #expect(windows(decode(#"{"primary":{"used_percent":"12.5","window_minutes":300.0}}"#))?.first?.usedPercent == 12.5)
        #expect(decode(#"{"primary":{"used_percent":5,"window_minutes":300.5}}"#) == .unrecognized)
    }

    // MARK: - Mapping

    @Test func windowsMapByLengthNotSlot() {
        let reading = RateReading(
            observedAt: testNow, bucketID: "codex", bucketName: nil,
            windows: [
                RateWindow(minutes: 10_080, usedPercent: 40, resetsAt: nil),
                RateWindow(minutes: 300, usedPercent: 10, resetsAt: nil),
                RateWindow(minutes: 180, usedPercent: 5, resetsAt: nil),
            ],
            planType: nil
        )
        let limits = CodexLimits.limits(of: reading)
        #expect(limits.map(\.window) == [.weekly, .fiveHour, .minutes(180)])
        #expect(limits.allSatisfy { $0.observedAt == testNow && !$0.resetIsEstimated })
    }

    @Test func planNames() {
        #expect(CodexLimits.planName("plus") == "Plus")
        #expect(CodexLimits.planName("pro") == "Pro")
        #expect(CodexLimits.planName("prolite") == "Pro Lite")
        #expect(CodexLimits.planName("team") == "Team")
        #expect(CodexLimits.planName("enterprise") == "Enterprise")
        #expect(CodexLimits.planName("  ") == nil)
        #expect(CodexLimits.planName(nil) == nil)
    }

    // MARK: - Lines

    @Test func sessionMetaDecodesOnlyWhatItNeeds() throws {
        let text = try CodexFixtures.rollout("subagent")
        let first = String(text.split(separator: "\n")[0])
        let meta = try #require(try JSONDecoder().decode(SessionMetaLine.self, from: Data(first.utf8)).meta)
        #expect(meta.id == CodexFixtures.threadID("subagent"))
        #expect(meta.source == .object)
        #expect(meta.threadSource == "subagent")
        #expect(meta.parentThreadID != nil)
        #expect(!meta.isRootNativeThread)
    }

    @Test func rootNativeThreads() {
        func meta(_ source: SessionMeta.Source, _ threadSource: String?) -> SessionMeta {
            SessionMeta(id: "x", timestamp: nil, cwd: nil, source: source, threadSource: threadSource)
        }
        #expect(meta(.name("vscode"), "user").isRootNativeThread)
        #expect(meta(.name("cli"), nil).isRootNativeThread)
        #expect(meta(.name("vscode"), nil).isRootNativeThread)
        #expect(!meta(.name("exec"), "user").isRootNativeThread)
        #expect(!meta(.name("exec"), nil).isRootNativeThread)
        #expect(!meta(.name("mcp"), nil).isRootNativeThread)
        #expect(!meta(.name("vscode"), "guardian_review").isRootNativeThread)
        #expect(!meta(.name("vscode"), "subagent").isRootNativeThread)
        #expect(!meta(.object, "user").isRootNativeThread)
        #expect(!meta(.missing, nil).isRootNativeThread)
        #expect(meta(.name("cli"), nil).isTerminal)
        #expect(!meta(.name("vscode"), "user").isTerminal)
    }
}
