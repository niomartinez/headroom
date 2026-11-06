import Darwin
import Foundation
import Testing
@testable import CodexKit

/// What CodexKit may touch (1.1 §0.1 invariant 2, §3.1) and the runtime probe (§3.5).
@Suite struct CodexAccessRulesTests {
    /// Every CodexKit source file.
    private static func sources() throws -> [(name: String, text: String)] {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CodexKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // HeadroomKit
            .appendingPathComponent("Sources/CodexKit", isDirectory: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".swift") }
        return try names.map { ($0, try String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8)) }
    }

    /// 1.1 §11.1 allowlist test: no CodexKit source names Codex's sign-in, config, caches, state databases or IPC
    /// socket, or calls `flock` (a shared lock would break Codex's `try_lock`).
    @Test func codexKitNeverNamesForbiddenFiles() throws {
        let sources = try Self.sources()
        #expect(sources.count >= 5)
        let forbidden = ["auth.json", "config.toml", "models_cache", "global-state", ".sqlite", "ipc", "flock"]
        for (name, text) in sources {
            for word in forbidden {
                #expect(!text.lowercased().contains(word), "\(name) mentions \(word)")
            }
        }
    }

    /// CodexKit builds every URL into the Codex folder through `CodexPaths`.
    @Test func codexKitBuildsNoPathsOfItsOwn() throws {
        for (name, text) in try Self.sources() {
            for literal in ["\".codex", "\"thread-writer-locks", "\"session_index", "\"external_agent", "\"sessions"] {
                #expect(!text.contains(literal), "\(name) builds a Codex path itself: \(literal)")
            }
        }
    }

    @Test func theProcessListCanBeReadOutsideTheSandbox() {
        let names = ProcessList.commandNames()
        #expect(names != nil)
        #expect(names?.isEmpty == false)
        // This test runner itself is in the list.
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        #expect(sysctl(&mib, 4, &info, &size, nil, 0) == 0)
        let own = withUnsafeBytes(of: info.kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        #expect(names?.contains(own) == true)
    }

    @Test func onlyAProcessNamedExactlyCodexCounts() {
        #expect(ProcessList.containsCodex(["launchd", "codex", "zsh"]))
        #expect(!ProcessList.containsCodex(["launchd", "codex-helper", "Codex", "node"]))
        #expect(!ProcessList.containsCodex([]))
    }

    /// A process named `codex` (a copy of `sleep`) is found by `sysctl(KERN_PROC_ALL)`.
    @Test func aRunningCodexProcessIsSeen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = directory.appendingPathComponent("codex")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: binary)
        let process = Process()
        process.executableURL = binary
        process.arguments = ["30"]
        try process.run()
        defer {
            process.terminate()
            process.waitUntilExit()
        }
        #expect(CodexRuntimeProbe.codexProcessExists() == true)
        #expect(CodexRuntimeProbe(appIsRunning: { false }).codexRunning() == true)
    }

    @Test func theAppCheckAloneIsEnough() {
        #expect(CodexRuntimeProbe(appIsRunning: { true }).codexRunning() == true)
    }
}
