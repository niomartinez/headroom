import Foundation
import Testing
@testable import SessionKit

@Suite struct SessionRegistryReaderTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func parsesEveryFieldWithMillisecondTimes() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("40001.json", data: fixture("registry-desktop"))

        let entries = try SessionRegistryReader(directory: dir.url).readEntries()

        #expect(entries == [
            RegistryEntry(
                sessionId: "11111111-2222-4333-8444-555555555555",
                pid: 40001,
                cwd: "/Users/tester/code/sample-app",
                entrypoint: "claude-desktop",
                kind: "interactive",
                status: "busy",
                name: "Refactor widget cache",
                startedAt: Date(timeIntervalSince1970: 1_790_240_000),
                statusUpdatedAt: Date(timeIntervalSince1970: 1_790_249_955.821),
                nameSource: "auto",
                processStartedAt: Date(timeIntervalSince1970: 1_790_244_000),
                version: "2.1.280",
                hostSessionId: "host-0001"
            ),
        ])
    }

    /// CLI 2.1.281 registers terminal sessions, with a name derived from the folder.
    @Test func parsesACliEntryWithADerivedName() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("51234.json", data: fixture("registry-cli-derived"))

        let entries = try SessionRegistryReader(directory: dir.url).readEntries()

        #expect(entries == [
            RegistryEntry(
                sessionId: "66666666-7777-4888-9999-aaaaaaaaaaaa",
                pid: 51234,
                cwd: "/Users/tester/code/hr-e2e café",
                entrypoint: "cli",
                kind: "interactive",
                status: "idle",
                name: "hr-e2e-caf-59",
                startedAt: Date(timeIntervalSince1970: 1_790_250_740.912),
                statusUpdatedAt: Date(timeIntervalSince1970: 1_790_250_741.020),
                nameSource: "derived",
                processStartedAt: Date(timeIntervalSince1970: 1_790_250_740),
                version: "2.1.281"
            ),
        ])
    }

    /// 1.1 §14.1: CLI 2.1.281 says what a waiting session waits for.
    @Test func parsesWaitingFor() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("48213.json", data: fixture("registry-cli-dialog-open"))

        let entry = try #require(try SessionRegistryReader(directory: dir.url).readEntries().first)

        #expect(entry.status == "waiting")
        #expect(entry.waitingFor == "dialog open")
        #expect(entry.version == "2.1.281")
        #expect(entry.hostSessionId == nil)
        #expect(entry.startedAt == Date(timeIntervalSince1970: 1_790_250_000))
        #expect(entry.statusUpdatedAt == Date(timeIntervalSince1970: 1_790_250_007.7))
    }

    /// `procStart` is `LC_ALL=C TZ=UTC ps -o lstart=`: `%a %b %e %H:%M:%S %Y`, so a day below 10 is
    /// space-padded. Anything else is ignored rather than guessed at.
    @Test(arguments: [
        ("Thu Sep 24 10:06:01 2026", 1_790_244_361.0),
        ("Thu Sep  3 16:27:07 2026", 1_788_452_827),
        ("Thu Sep 03 16:27:07 2026", 1_788_452_827),
        (" Wed Sep 23 21:06:37 2026\n", 1_790_197_597),
        ("Sat Feb 28 23:59:59 2026", 1_772_323_199),
        ("Tue Dec 31 23:59:59 2024", 1_735_689_599),
    ] as [(String, TimeInterval)])
    func readsProcStartAsUTC(_ procStart: String, _ expected: TimeInterval) throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let json = try String(data: JSONSerialization.data(withJSONObject: ["pid": 9, "sessionId": "s-9", "procStart": procStart]),
                              encoding: .utf8)
        try dir.write("9.json", try #require(json))

        let entries = try SessionRegistryReader(directory: dir.url).readEntries()

        #expect(entries.map(\.processStartedAt) == [Date(timeIntervalSince1970: expected)])
    }

    @Test(arguments: [
        "", "yesterday", "1790244361", "133700000000000000",
        "Thu Sep 24 10:06 2026", "Thu Sep 24 10:06:01", "Sep 24 10:06:01 2026", "Thu Sep 24 10:06:01 2026 UTC",
        "Thu Foo 24 10:06:01 2026", "Thu Sep 31 10:06:01 2026", "Thu Sep 0 10:06:01 2026",
        "Thu Sep 24 24:06:01 2026", "Thu Sep 24 10:60:01 2026", "Thu Sep 24 10:06:60 2026",
        "Thu Sep 24 1a:06:01 2026", "Thu Sep +4 10:06:01 2026", "Thu Sep 24 10:06:01 -26",
        "Xyz Sep 24 10:06:01 2026", "2026-09-24T10:06:01Z",
    ])
    func ignoresProcStartInAnyOtherForm(_ procStart: String) throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let json = try String(data: JSONSerialization.data(withJSONObject: ["pid": 9, "sessionId": "s-9", "procStart": procStart]),
                              encoding: .utf8)
        try dir.write("9.json", try #require(json))

        let entries = try SessionRegistryReader(directory: dir.url).readEntries()

        #expect(entries.map(\.sessionId) == ["s-9"])
        #expect(entries.map(\.processStartedAt) == [nil])
    }

    /// Claude Code reads `procStartFt ?? procStart`; on macOS only `procStart` is written, but a
    /// `procStartFt` in the same form is read when `procStart` is missing.
    @Test func readsProcStartFtOnlyInPlaceOfProcStart() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("1.json", #"{"pid":1,"sessionId":"s-1","procStartFt":"Thu Sep 24 10:06:01 2026"}"#)
        try dir.write("2.json", #"{"pid":2,"sessionId":"s-2","procStart":"Thu Sep 24 10:00:00 2026","procStartFt":"Thu Sep 24 10:06:01 2026"}"#)
        try dir.write("3.json", #"{"pid":3,"sessionId":"s-3","procStart":"garbage","procStartFt":"Thu Sep 24 10:06:01 2026"}"#)
        try dir.write("4.json", #"{"pid":4,"sessionId":"s-4","procStartFt":"133700000000000000"}"#)

        let entries = try SessionRegistryReader(directory: dir.url).readEntries()

        #expect(entries.map(\.processStartedAt) == [
            Date(timeIntervalSince1970: 1_790_244_361),
            Date(timeIntervalSince1970: 1_790_244_000),
            Date(timeIntervalSince1970: 1_790_244_361),
            nil,
        ])
    }

    @Test func ignoresNonJSONFilesAndMalformedJSON() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("100.json", #"{"pid":100,"sessionId":"s-100","entrypoint":"cli"}"#)
        try dir.write("100.0123abcd.key", #"{"pid":101,"sessionId":"s-key"}"#)
        try dir.write("notes.txt", #"{"pid":102,"sessionId":"s-txt"}"#)
        try dir.write("103.json", #"{"pid":103,"sessionId":"#)
        try dir.write("104.json", "")
        try dir.write("105.json", #"["pid",105]"#)
        try dir.write("106.json", "not json at all")
        try dir.write("107.json", data: Data([0xFF, 0xFE, 0x00, 0x7B]))

        let entries = try SessionRegistryReader(directory: dir.url).readEntries()

        #expect(entries.map(\.sessionId) == ["s-100"])
    }

    @Test func skipsEntriesWithoutUsableIdOrPid() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("1.json", #"{"pid":1,"sessionId":""}"#)
        try dir.write("2.json", #"{"pid":2}"#)
        try dir.write("3.json", #"{"sessionId":"s-3"}"#)
        try dir.write("4.json", #"{"pid":"4","sessionId":"s-4"}"#)
        try dir.write("5.json", #"{"pid":-5,"sessionId":"s-5"}"#)
        try dir.write("6.json", #"{"pid":99999999999,"sessionId":"s-6"}"#)
        try dir.write("7.json", #"{"pid":7.5,"sessionId":"s-7"}"#)
        try dir.write("8.json", #"{"pid":true,"sessionId":"s-8"}"#)
        try dir.write("9.json", #"{"pid":9,"sessionId":"s-9"}"#)

        let entries = try SessionRegistryReader(directory: dir.url).readEntries()

        #expect(entries.map(\.sessionId) == ["s-9"])
    }

    @Test func wrongTypedOptionalFieldsBecomeNil() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("9.json", """
        {"pid":9,"sessionId":"s-9","cwd":42,"entrypoint":null,"kind":["x"],"status":{"a":1},
         "name":false,"startedAt":"yesterday","statusUpdatedAt":true,"nameSource":1,"procStart":1790244361,
         "waitingFor":7,"version":2.1,"hostSessionId":{}}
        """)

        let entries = try SessionRegistryReader(directory: dir.url).readEntries()

        #expect(entries == [
            RegistryEntry(sessionId: "s-9", pid: 9, cwd: nil, entrypoint: nil, kind: nil, status: nil,
                          name: nil, startedAt: nil, statusUpdatedAt: nil),
        ])
    }

    @Test func missingDirectoryReturnsEmpty() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let missing = dir.url.appendingPathComponent("nope/sessions", isDirectory: true)

        #expect(try SessionRegistryReader(directory: missing).readEntries() == [])
    }

    @Test func unreadableDirectoryThrows() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("1.json", #"{"pid":1,"sessionId":"s-1"}"#)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.url.path)

        #expect(throws: SessionRegistryError.directoryUnreadable) {
            try SessionRegistryReader(directory: dir.url).readEntries()
        }
    }

    /// `~/.claude/sessions` may be a symlink (dotfile setups); it is readable, so it must not throw.
    @Test func symlinkedDirectoryIsRead() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let real = dir.url.appendingPathComponent("real-sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
        try Data(#"{"pid":7,"sessionId":"s-7","entrypoint":"claude-desktop"}"#.utf8)
            .write(to: real.appendingPathComponent("7.json"))
        let link = dir.url.appendingPathComponent("sessions")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let entries = try SessionRegistryReader(directory: link).readEntries()

        #expect(entries.map(\.sessionId) == ["s-7"])
    }

    @Test func fileInPlaceOfDirectoryThrows() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let file = try dir.write("sessions", "plain file")

        #expect(throws: SessionRegistryError.directoryUnreadable) {
            try SessionRegistryReader(directory: file).readEntries()
        }
    }

    @Test func skipsOversizedDirectoriesAndSpecialFiles() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let padding = String(repeating: " ", count: 2 * 1024 * 1024)
        try dir.write("1.json", #"{"pid":1,"sessionId":"s-big","name":"\#(padding)"}"#)
        try FileManager.default.createDirectory(
            at: dir.url.appendingPathComponent("2.json", isDirectory: true), withIntermediateDirectories: false)
        #expect(mkfifo(dir.url.appendingPathComponent("3.json").path, 0o644) == 0)
        try dir.write("4.json", #"{"pid":4,"sessionId":"s-4"}"#)

        let entries = try SessionRegistryReader(directory: dir.url).readEntries()

        #expect(entries.map(\.sessionId) == ["s-4"])
    }

    @Test func survivesDeeplyNestedJSON() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let nested = String(repeating: "[", count: 100_000) + String(repeating: "]", count: 100_000)
        try dir.write("1.json", #"{"pid":1,"sessionId":"s-1","junk":\#(nested)}"#)
        try dir.write("2.json", nested)
        try dir.write("3.json", #"{"pid":3,"sessionId":"s-3"}"#)

        let entries = try SessionRegistryReader(directory: dir.url).readEntries()

        #expect(entries.map(\.sessionId) == ["s-3"])
    }

    @Test func readsSeveralEntries() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("20.json", #"{"pid":20,"sessionId":"s-20","entrypoint":"sdk-cli"}"#)
        try dir.write("10.json", #"{"pid":10,"sessionId":"s-10","entrypoint":"claude-desktop"}"#)

        let entries = try SessionRegistryReader(directory: dir.url).readEntries()

        #expect(Set(entries.map(\.pid)) == [10, 20])
    }
}
