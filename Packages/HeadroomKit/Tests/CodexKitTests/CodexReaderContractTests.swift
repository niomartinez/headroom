import Foundation
import HeadroomModel
import Testing
@testable import CodexKit

/// The public contract other streams build against (1.1 §3, §7).
@Suite struct CodexReaderContractTests {
    private struct FixedRuntime: CodexRuntimeProbing {
        var running: Bool?
        func codexRunning() -> Bool? { running }
    }

    @Test func readerUsesCodexPathsForItsFolder() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString)")
        let reader = CodexReader(codexHome: home, runtime: FixedRuntime(running: nil))
        #expect(reader.paths == CodexPaths(codexDirectory: home))
        #expect(reader.paths.sessionsDirectory.lastPathComponent == "sessions")
    }

    @Test func readingIsCodexUsage() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString)")
        let provider: any CodexReadingProviding = CodexReader(codexHome: home, runtime: FixedRuntime(running: false))
        let reading = provider.read(now: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(reading.usage.tool == .codex)
        #expect(reading.sessions.allSatisfy { $0.tool == .codex })
    }
}
