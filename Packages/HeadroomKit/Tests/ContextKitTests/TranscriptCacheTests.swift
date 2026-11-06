import Foundation
import Testing
@testable import ContextKit

@Suite("TranscriptContextReader cache by (path, size, mtime) (spec §2.3)")
struct TranscriptCacheTests {
    @Test func unchangedFileIsNotReadAgain() throws {
        try withTempDirectory { tmp in
            let url = tmp.appendingPathComponent("session.jsonl")
            try url.write(Fixture.assistant(model: "claude-a"))
            let reader = TranscriptContextReader()

            let first = reader.latestUsage(at: url)
            let second = reader.latestUsage(at: url)
            #expect(first?.model == "claude-a")
            #expect(second == first)
            #expect(reader.readCount == 1)
        }
    }

    @Test func appendingAnAssistantLineGivesTheNewValue() throws {
        try withTempDirectory { tmp in
            let url = tmp.appendingPathComponent("session.jsonl")
            try url.write(Fixture.assistant(model: "claude-a", cacheRead: 1_000))
            let reader = TranscriptContextReader()
            #expect(reader.latestUsage(at: url)?.model == "claude-a")

            try url.append(Fixture.user() + Fixture.assistant(model: "claude-b", cacheRead: 9_000))
            let updated = try #require(reader.latestUsage(at: url))
            #expect(updated.model == "claude-b")
            #expect(updated.usedTokens == 10 + 200 + 9_000 + 40)
            #expect(reader.readCount == 2)
        }
    }

    @Test func sameSizeButNewModificationTimeIsReadAgain() throws {
        try withTempDirectory { tmp in
            let url = tmp.appendingPathComponent("session.jsonl")
            try url.write(Fixture.assistant(model: "claude-a"))
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: url.path)
            let reader = TranscriptContextReader()
            #expect(reader.latestUsage(at: url)?.model == "claude-a")

            try url.write(Fixture.assistant(model: "claude-b"))
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_000)], ofItemAtPath: url.path)
            #expect(reader.latestUsage(at: url)?.model == "claude-b")
            #expect(reader.readCount == 2)
        }
    }

    @Test func filesWithNothingUsableAreCachedToo() throws {
        try withTempDirectory { tmp in
            let url = tmp.appendingPathComponent("session.jsonl")
            try url.write(Fixture.user())
            let reader = TranscriptContextReader()
            #expect(reader.latestUsage(at: url) == nil)
            #expect(reader.latestUsage(at: url) == nil)
            #expect(reader.readCount == 1)
        }
    }

    @Test func deletedFileReturnsNilAndIsReadAgainWhenRecreated() throws {
        try withTempDirectory { tmp in
            let url = tmp.appendingPathComponent("session.jsonl")
            try url.write(Fixture.assistant(model: "claude-a"))
            let reader = TranscriptContextReader()
            #expect(reader.latestUsage(at: url)?.model == "claude-a")

            try FileManager.default.removeItem(at: url)
            #expect(reader.latestUsage(at: url) == nil)

            try url.write(Fixture.assistant(model: "claude-b"))
            #expect(reader.latestUsage(at: url)?.model == "claude-b")
            #expect(reader.readCount == 2)
        }
    }

    @Test func eachFileHasItsOwnEntry() throws {
        try withTempDirectory { tmp in
            let a = tmp.appendingPathComponent("a.jsonl")
            let b = tmp.appendingPathComponent("b.jsonl")
            try a.write(Fixture.assistant(model: "claude-a"))
            try b.write(Fixture.assistant(model: "claude-b"))
            let reader = TranscriptContextReader()
            for _ in 0..<3 {
                #expect(reader.latestUsage(at: a)?.model == "claude-a")
                #expect(reader.latestUsage(at: b)?.model == "claude-b")
            }
            #expect(reader.readCount == 2)
        }
    }

    @Test func concurrentReadsAreSafe() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ContextKitTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = try (0..<8).map { i in
            let url = dir.appendingPathComponent("s\(i).jsonl")
            try url.write(Fixture.assistant(model: "claude-\(i)"))
            return url
        }
        let reader = TranscriptContextReader()
        let models = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<4 {
                for url in urls {
                    group.addTask { reader.latestUsage(at: url)?.model }
                }
            }
            var all: [String?] = []
            for await model in group { all.append(model) }
            return all
        }
        #expect(models.count == 32)
        #expect(Set(models.compactMap { $0 }) == Set((0..<8).map { "claude-\($0)" }))
    }
}
