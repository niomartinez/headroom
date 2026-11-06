import Foundation
import Testing
@testable import SessionKit

@Suite struct BridgeSessionReaderTests {
    private let id = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"

    private func statusLineFixture() throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: "statusline-payload", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func mergesHookAndStatusLineIntoOneRecord() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("\(id).hook.json", """
        {"v":1,"ts":1790250000,"pid":50001,"event":"Notification","session_id":"\(id)",
         "cwd":"/Users/tester/code/demo",
         "transcript_path":"/Users/tester/.claude/projects/-Users-tester-code-demo/\(id).jsonl",
         "notification_type":"permission_prompt"}
        """)
        try dir.write("\(id).statusline.json", data: statusLineFixture())

        let records = BridgeSessionReader(directory: dir.url).readRecords()

        #expect(records == [
            BridgeSessionRecord(
                sessionId: id,
                pid: 50001,
                cwd: "/Users/tester/code/demo",
                transcriptPath: "/Users/tester/.claude/projects/-Users-tester-code-demo/\(id).jsonl",
                lastEvent: "Notification",
                lastEventAt: Date(timeIntervalSince1970: 1_790_250_000),
                notificationType: "permission_prompt",
                statusLineAt: Date(timeIntervalSince1970: 1_790_250_060),
                contextWindowSize: 200_000,
                contextUsedPercent: 26,
                modelId: "claude-haiku-4-5"
            ),
        ])
        #expect(records.first?.lastSeenAt == Date(timeIntervalSince1970: 1_790_250_060))
    }

    @Test func hookOnlyRecordTreatsEmptyStringsAsMissing() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("s-1.hook.json", """
        {"v":1,"ts":1790250000.5,"pid":123,"event":"Stop","session_id":"s-1","cwd":"",
         "transcript_path":"","notification_type":""}
        """)

        let records = BridgeSessionReader(directory: dir.url).readRecords()

        #expect(records == [
            BridgeSessionRecord(
                sessionId: "s-1", pid: 123, lastEvent: "Stop",
                lastEventAt: Date(timeIntervalSince1970: 1_790_250_000.5)),
        ])
    }

    @Test func statusLineOnlyRecordWithStringModelAndWorkspaceDir() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("s-2.statusline.json", """
        {"v":1,"ts":1790250100,"pid":77,"payload":{"session_id":"s-2","model":"claude-opus-5-5",
         "workspace":{"current_dir":"/Users/tester/code/other"},
         "context_window":{"used_percentage":71.5,"context_window_size":1000000}}}
        """)

        let records = BridgeSessionReader(directory: dir.url).readRecords()

        #expect(records == [
            BridgeSessionRecord(
                sessionId: "s-2", pid: 77, cwd: "/Users/tester/code/other",
                statusLineAt: Date(timeIntervalSince1970: 1_790_250_100),
                contextWindowSize: 1_000_000, contextUsedPercent: 71.5, modelId: "claude-opus-5-5"),
        ])
    }

    @Test func payloadCwdWinsOverWorkspaceDir() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("s-3.statusline.json", """
        {"v":1,"ts":1790250100,"pid":77,"payload":{"cwd":"/Users/tester/code/sub",
         "workspace":{"current_dir":"/Users/tester/code/root"}}}
        """)

        let records = BridgeSessionReader(directory: dir.url).readRecords()

        #expect(records.map(\.cwd) == ["/Users/tester/code/sub"])
    }

    @Test func statusLineWithoutContextOrModelLeavesThemNil() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("s-4.statusline.json", """
        {"v":1,"ts":1790250100,"payload":{"model":{"display_name":"Mystery"},
         "context_window":{"used_percentage":"lots","context_window_size":null}}}
        """)

        let records = BridgeSessionReader(directory: dir.url).readRecords()

        #expect(records == [
            BridgeSessionRecord(sessionId: "s-4", statusLineAt: Date(timeIntervalSince1970: 1_790_250_100)),
        ])
    }

    @Test func newerFileSuppliesSharedFields() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("s-5.hook.json", """
        {"v":1,"ts":1790250000,"pid":10,"event":"PreToolUse","cwd":"/old","transcript_path":"/old.jsonl"}
        """)
        try dir.write("s-5.statusline.json", """
        {"v":1,"ts":1790250200,"pid":11,"payload":{"cwd":"/new","transcript_path":"/new.jsonl"}}
        """)
        try dir.write("s-6.hook.json", """
        {"v":1,"ts":1790250300,"pid":20,"event":"Stop","cwd":"/newer"}
        """)
        try dir.write("s-6.statusline.json", """
        {"v":1,"ts":1790250200,"pid":21,"payload":{"cwd":"/older","transcript_path":"/only-here.jsonl"}}
        """)

        let records = BridgeSessionReader(directory: dir.url).readRecords()
            .sorted { $0.sessionId < $1.sessionId }

        #expect(records.map(\.pid) == [11, 20])
        #expect(records.map(\.cwd) == ["/new", "/newer"])
        #expect(records.map(\.transcriptPath) == ["/new.jsonl", "/only-here.jsonl"])
    }

    @Test func malformedFilesAreSkippedButTheirPartnerStillCounts() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("s-7.hook.json", #"{"v":1,"ts":1790250000,"pid":5,"event":"Stop"}"#)
        try dir.write("s-7.statusline.json", #"{"v":1,"ts":17902"#)
        try dir.write("s-8.hook.json", "garbage")
        try dir.write("s-8.statusline.json", #"["not","an","object"]"#)
        try dir.write("s-9.statusline.json", #"{"v":1,"ts":1790250000,"payload":"oops"}"#)

        let records = BridgeSessionReader(directory: dir.url).readRecords()
            .sorted { $0.sessionId < $1.sessionId }

        #expect(records.map(\.sessionId) == ["s-7", "s-9"])
        #expect(records.first?.statusLineAt == nil)
        #expect(records.last?.statusLineAt == Date(timeIntervalSince1970: 1_790_250_000))
        #expect(records.last?.modelId == nil)
    }

    @Test func ignoresUnrelatedAndTemporaryFiles() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let hook = #"{"v":1,"ts":1790250000,"pid":5,"event":"Stop"}"#
        try dir.write("s-10.hook.json", hook)
        try dir.write("s-11.hook.json.tmp.4242", hook)
        try dir.write("s-12.json", hook)
        try dir.write(".hook.json", hook)
        try dir.write("readme.txt", hook)
        try dir.write("statusline-latest.json", hook)

        let records = BridgeSessionReader(directory: dir.url).readRecords()

        #expect(records.map(\.sessionId) == ["s-10"])
    }

    @Test func sessionIdInsideTheFileWinsOverTheFileName() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("s-16.hook.json", #"{"v":1,"ts":1790250000,"pid":5,"event":"Stop","session_id":"s-16"}"#)
        try dir.write("tmp.0042.hook.json", #"{"v":1,"ts":1790250300,"pid":5,"event":"PreToolUse","session_id":"s-16"}"#)
        try dir.write("tmp.0043.statusline.json", #"{"v":1,"ts":1790250200,"payload":{"session_id":"s-16","cwd":"/a"}}"#)

        let records = BridgeSessionReader(directory: dir.url).readRecords()

        #expect(records == [
            BridgeSessionRecord(
                sessionId: "s-16", pid: 5, cwd: "/a", lastEvent: "PreToolUse",
                lastEventAt: Date(timeIntervalSince1970: 1_790_250_300),
                statusLineAt: Date(timeIntervalSince1970: 1_790_250_200)),
        ])
    }

    @Test func rejectsInvalidPidsAndTimes() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("s-13.hook.json", #"{"v":1,"ts":"now","pid":0,"event":42}"#)
        try dir.write("s-14.hook.json", #"{"v":1,"ts":true,"pid":4294967296,"event":"Stop"}"#)

        let records = BridgeSessionReader(directory: dir.url).readRecords()
            .sorted { $0.sessionId < $1.sessionId }

        #expect(records == [
            BridgeSessionRecord(sessionId: "s-13"),
            BridgeSessionRecord(sessionId: "s-14", lastEvent: "Stop"),
        ])
    }

    @Test func missingDirectoryReturnsEmpty() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }

        let reader = BridgeSessionReader(directory: dir.url.appendingPathComponent("headroom/sessions"))

        #expect(reader.readRecords() == [])
    }

    @Test func symlinkedDirectoryIsRead() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let real = dir.url.appendingPathComponent("real-sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
        try Data(#"{"v":1,"ts":1790250000,"pid":5,"event":"Stop","session_id":"s-1"}"#.utf8)
            .write(to: real.appendingPathComponent("s-1.hook.json"))
        let link = dir.url.appendingPathComponent("sessions")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        #expect(BridgeSessionReader(directory: link).readRecords().map(\.sessionId) == ["s-1"])
    }

    @Test func unreadableDirectoryReturnsEmpty() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("s-1.hook.json", #"{"v":1,"ts":1790250000,"pid":5,"event":"Stop"}"#)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.url.path)

        #expect(BridgeSessionReader(directory: dir.url).readRecords() == [])
    }

    @Test func skipsOversizedFiles() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let padding = String(repeating: " ", count: 2 * 1024 * 1024)
        try dir.write("s-15.statusline.json", #"{"v":1,"ts":1790250000,"payload":{"cwd":"/x"}}\#(padding)"#)

        #expect(BridgeSessionReader(directory: dir.url).readRecords() == [])
    }
}
