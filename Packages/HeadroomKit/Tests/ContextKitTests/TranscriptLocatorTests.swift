import Foundation
import os
import Testing
@testable import ContextKit

@Suite("TranscriptLocator (spec §2.3)")
struct TranscriptLocatorTests {
    static let sessionID = "11111111-2222-4333-8444-555555555555"

    /// `<tmp>/projects/<project>/<id>.jsonl`, created with one synthetic line.
    @discardableResult
    static func makeTranscript(in projects: URL, project: String, id: String = sessionID) throws -> URL {
        let url = projects.appendingPathComponent(project, isDirectory: true)
            .appendingPathComponent("\(id).jsonl", isDirectory: false)
        try url.write(Fixture.assistant())
        return url
    }

    @Test func existingHintIsUsed() throws {
        try withTempDirectory { tmp in
            let projects = tmp.appendingPathComponent("projects", isDirectory: true)
            try Self.makeTranscript(in: projects, project: "-Users-test-app")
            let hinted = tmp.appendingPathComponent("elsewhere/\(Self.sessionID).jsonl")
            try hinted.write(Fixture.assistant())

            let locator = TranscriptLocator(projectsDirectory: projects)
            let found = locator.transcriptURL(forSession: Self.sessionID, hint: hinted.path)
            #expect(found?.path == hinted.path)
            #expect(locator.searchCount == 0)
        }
    }

    @Test func missingHintFallsBackToSearch() throws {
        try withTempDirectory { tmp in
            let projects = tmp.appendingPathComponent("projects", isDirectory: true)
            let expected = try Self.makeTranscript(in: projects, project: "-Users-test-app")
            let locator = TranscriptLocator(projectsDirectory: projects)
            let found = locator.transcriptURL(forSession: Self.sessionID, hint: tmp.appendingPathComponent("gone.jsonl").path)
            #expect(found?.path == expected.path)
        }
    }

    @Test(arguments: [
        "relative/path.jsonl",
        "",
        "/",
    ])
    func unusableHintsFallBackToSearch(_ hint: String) throws {
        try withTempDirectory { tmp in
            let projects = tmp.appendingPathComponent("projects", isDirectory: true)
            let expected = try Self.makeTranscript(in: projects, project: "-Users-test-app")
            let found = TranscriptLocator(projectsDirectory: projects).transcriptURL(forSession: Self.sessionID, hint: hint)
            #expect(found?.path == expected.path)
        }
    }

    @Test func hintThatIsADirectoryOrNotATranscriptIsIgnored() throws {
        try withTempDirectory { tmp in
            let projects = tmp.appendingPathComponent("projects", isDirectory: true)
            let expected = try Self.makeTranscript(in: projects, project: "-Users-test-app")
            let directoryHint = tmp.appendingPathComponent("dir.jsonl", isDirectory: true)
            try FileManager.default.createDirectory(at: directoryHint, withIntermediateDirectories: true)
            let textHint = tmp.appendingPathComponent("notes.txt")
            try textHint.write("not a transcript")

            let locator = TranscriptLocator(projectsDirectory: projects)
            #expect(locator.transcriptURL(forSession: Self.sessionID, hint: directoryHint.path)?.path == expected.path)
            #expect(locator.transcriptURL(forSession: Self.sessionID, hint: textHint.path)?.path == expected.path)
        }
    }

    @Test(arguments: ["-Users-test-app", "--leading-dashes", "plain-project"])
    func searchFindsTranscriptInAnyProjectDirectory(_ project: String) throws {
        try withTempDirectory { tmp in
            let projects = tmp.appendingPathComponent("projects", isDirectory: true)
            try Self.makeTranscript(in: projects, project: "-Users-test-other", id: "99999999-2222-4333-8444-555555555555")
            let expected = try Self.makeTranscript(in: projects, project: project)
            let found = TranscriptLocator(projectsDirectory: projects).transcriptURL(forSession: Self.sessionID, hint: nil)
            #expect(found?.path == expected.path)
        }
    }

    @Test func notFoundReturnsNil() throws {
        try withTempDirectory { tmp in
            let projects = tmp.appendingPathComponent("projects", isDirectory: true)
            try Self.makeTranscript(in: projects, project: "-Users-test-app", id: "99999999-2222-4333-8444-555555555555")
            #expect(TranscriptLocator(projectsDirectory: projects).transcriptURL(forSession: Self.sessionID, hint: nil) == nil)
        }
    }

    @Test func missingProjectsDirectoryReturnsNil() throws {
        try withTempDirectory { tmp in
            let locator = TranscriptLocator(projectsDirectory: tmp.appendingPathComponent("absent", isDirectory: true))
            #expect(locator.transcriptURL(forSession: Self.sessionID, hint: nil) == nil)
        }
    }

    @Test(arguments: ["", "../escape", "a/b", "nul\u{0}byte", String(repeating: "a", count: 300)])
    func implausibleSessionIDsAreNotSearched(_ id: String) throws {
        try withTempDirectory { tmp in
            let projects = tmp.appendingPathComponent("projects", isDirectory: true)
            try Self.makeTranscript(in: projects, project: "-Users-test-app")
            let locator = TranscriptLocator(projectsDirectory: projects)
            #expect(locator.transcriptURL(forSession: id, hint: nil) == nil)
            #expect(locator.searchCount == 0)
        }
    }

    @Test func prefersTheMostRecentlyModifiedMatch() throws {
        try withTempDirectory { tmp in
            let projects = tmp.appendingPathComponent("projects", isDirectory: true)
            let older = try Self.makeTranscript(in: projects, project: "-Users-test-a")
            let newer = try Self.makeTranscript(in: projects, project: "-Users-test-b")
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: older.path)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_000)], ofItemAtPath: newer.path)
            let found = TranscriptLocator(projectsDirectory: projects).transcriptURL(forSession: Self.sessionID, hint: nil)
            #expect(found?.path == newer.path)
        }
    }

    @Test func cachesTheMappingButReverifiesTheFile() throws {
        try withTempDirectory { tmp in
            let projects = tmp.appendingPathComponent("projects", isDirectory: true)
            let first = try Self.makeTranscript(in: projects, project: "-Users-test-app")
            let locator = TranscriptLocator(projectsDirectory: projects)

            #expect(locator.transcriptURL(forSession: Self.sessionID, hint: nil)?.path == first.path)
            #expect(locator.transcriptURL(forSession: Self.sessionID, hint: nil)?.path == first.path)
            #expect(locator.searchCount == 1)

            // A copy shares the cache.
            let copy = locator
            #expect(copy.transcriptURL(forSession: Self.sessionID, hint: nil)?.path == first.path)
            #expect(locator.searchCount == 1)

            // The cached file disappears: search again and find it in its new place.
            try FileManager.default.removeItem(at: first)
            let moved = try Self.makeTranscript(in: projects, project: "-Users-test-moved")
            #expect(locator.transcriptURL(forSession: Self.sessionID, hint: nil)?.path == moved.path)
            #expect(locator.searchCount == 2)

            // Gone for good: nil, not cached as found; the miss itself is remembered for a while.
            try FileManager.default.removeItem(at: moved)
            #expect(locator.transcriptURL(forSession: Self.sessionID, hint: nil) == nil)
            #expect(locator.transcriptURL(forSession: Self.sessionID, hint: nil) == nil)
            #expect(locator.searchCount == 3)
        }
    }

    // MARK: Misses (a session without a transcript must not scan projects/ on every 2 s poll)

    @Test func missesAreRememberedForTenSeconds() throws {
        try withTempDirectory { tmp in
            let projects = tmp.appendingPathComponent("projects", isDirectory: true)
            try Self.makeTranscript(in: projects, project: "-Users-test-app", id: "99999999-2222-4333-8444-555555555555")
            let clock = ManualUptime()
            let locator = TranscriptLocator(projectsDirectory: projects, uptime: clock.read)

            for _ in 0..<5 {
                #expect(locator.transcriptURL(forSession: Self.sessionID, hint: nil) == nil)
                clock.advance(by: 1.875)
            }
            #expect(locator.searchCount == 1)

            clock.advance(by: 0.625) // 10 s after the miss
            #expect(locator.transcriptURL(forSession: Self.sessionID, hint: nil) == nil)
            #expect(locator.searchCount == 2)
        }
    }

    @Test func aNewTranscriptIsFoundWithinTenSeconds() throws {
        try withTempDirectory { tmp in
            let projects = tmp.appendingPathComponent("projects", isDirectory: true)
            try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
            let clock = ManualUptime()
            let locator = TranscriptLocator(projectsDirectory: projects, uptime: clock.read)
            #expect(locator.transcriptURL(forSession: Self.sessionID, hint: nil) == nil)

            clock.advance(by: 1)
            let created = try Self.makeTranscript(in: projects, project: "-Users-test-new")
            clock.advance(by: 8.75)
            #expect(locator.transcriptURL(forSession: Self.sessionID, hint: nil) == nil)
            clock.advance(by: 0.25)
            #expect(locator.transcriptURL(forSession: Self.sessionID, hint: nil)?.path == created.path)
            #expect(locator.searchCount == 2)

            // Found locations are cached as before: no further searches.
            clock.advance(by: 60)
            #expect(locator.transcriptURL(forSession: Self.sessionID, hint: nil)?.path == created.path)
            #expect(locator.searchCount == 2)
        }
    }

    @Test func aRememberedMissDoesNotHideAUsableHintOrOtherSessions() throws {
        try withTempDirectory { tmp in
            let projects = tmp.appendingPathComponent("projects", isDirectory: true)
            let other = try Self.makeTranscript(in: projects, project: "-Users-test-app", id: "99999999-2222-4333-8444-555555555555")
            let clock = ManualUptime()
            let locator = TranscriptLocator(projectsDirectory: projects, uptime: clock.read)
            #expect(locator.transcriptURL(forSession: Self.sessionID, hint: nil) == nil)

            let hinted = tmp.appendingPathComponent("elsewhere/\(Self.sessionID).jsonl")
            try hinted.write(Fixture.assistant())
            #expect(locator.transcriptURL(forSession: Self.sessionID, hint: hinted.path)?.path == hinted.path)
            #expect(locator.transcriptURL(forSession: "99999999-2222-4333-8444-555555555555", hint: nil)?.path == other.path)
            #expect(locator.searchCount == 2)
        }
    }

    @Test func aClockThatGoesBackwardsDoesNotPinAMiss() throws {
        try withTempDirectory { tmp in
            let projects = tmp.appendingPathComponent("projects", isDirectory: true)
            try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
            let clock = ManualUptime(start: 1_000)
            let locator = TranscriptLocator(projectsDirectory: projects, uptime: clock.read)
            #expect(locator.transcriptURL(forSession: Self.sessionID, hint: nil) == nil)
            clock.advance(by: -500)
            #expect(locator.transcriptURL(forSession: Self.sessionID, hint: nil) == nil)
            #expect(locator.searchCount == 2)
        }
    }
}

/// A monotonic clock the test moves by hand.
final class ManualUptime: Sendable {
    private let now: OSAllocatedUnfairLock<TimeInterval>

    init(start: TimeInterval = 100) {
        now = OSAllocatedUnfairLock(initialState: start)
    }

    var read: @Sendable () -> TimeInterval {
        { [now] in now.withLock { $0 } }
    }

    func advance(by seconds: TimeInterval) {
        now.withLock { $0 += seconds }
    }
}
