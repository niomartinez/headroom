import Foundation
import Testing
@testable import HeadroomModel

@Suite struct PathsTests {
    private let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)

    @Test func codexPaths() throws {
        let paths = CodexPaths.standard(home: home)
        #expect(paths.codexDirectory.path == "/Users/me/.codex")
        #expect(paths.sessionsDirectory.path == "/Users/me/.codex/sessions")
        #expect(paths.sessionIndexFile.path == "/Users/me/.codex/session_index.jsonl")
        #expect(paths.importsFile.path == "/Users/me/.codex/external_agent_session_imports.json")
        #expect(paths.writerLocksDirectory.path == "/Users/me/.codex/thread-writer-locks")
        #expect(paths.writerLockFile(threadID: "01a0beba-55ec-7ac1-84a7-16d9f0a456e0").path
            == "/Users/me/.codex/thread-writer-locks/01a0beba-55ec-7ac1-84a7-16d9f0a456e0.lock")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 8 * 3600))
        // 2026-09-03 20:30 UTC is already Sep 4 in UTC+8, where Codex names the folder in local time.
        #expect(paths.sessionsDayDirectory(for: utc("2026-09-03T20:30:00Z"), calendar: calendar).path
            == "/Users/me/.codex/sessions/2026/09/04")
    }

    @Test func copilotPaths() {
        let paths = CopilotPaths.standard(home: home)
        #expect(paths.copilotDirectory.path == "/Users/me/.copilot")
        #expect(paths.hooksFile.path == "/Users/me/.copilot/hooks/headroom.json")
        #expect(paths.bridgeDirectory.path == "/Users/me/.copilot/headroom")
        #expect(paths.bridgeScriptFile.path == "/Users/me/.copilot/headroom/bridge.sh")
        #expect(paths.bridgeSessionsDirectory.path == "/Users/me/.copilot/headroom/sessions")
        #expect(paths.logsDirectory.path == "/Users/me/.copilot/logs")
    }
}
