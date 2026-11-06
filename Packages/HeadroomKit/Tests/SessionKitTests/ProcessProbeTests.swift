import Foundation
import Testing
@testable import SessionKit

/// `SystemProcessProbe` against real processes this test starts (and always stops).
@Suite struct SystemProcessProbeTests {
    private let probe = SystemProcessProbe()

    /// Starts `/bin/sleep`, runs `body` with its pid, then stops it.
    private func withSleepingChild(_ body: (Int32) throws -> Void) throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer {
            child.terminate()
            child.waitUntilExit()
        }
        try body(child.processIdentifier)
    }

    @Test func ownProcessHasAStartTimeInThePast() throws {
        let started = try #require(probe.startTime(pid: getpid()))

        #expect(started <= Date())
        #expect(probe.isAlive(pid: getpid()))
    }

    @Test func childStartTimeIsWhenItWasLaunched() throws {
        let before = Date()
        try withSleepingChild { pid in
            let after = Date()
            let started = try #require(probe.startTime(pid: pid))

            #expect(started >= before.addingTimeInterval(-1))
            #expect(started <= after.addingTimeInterval(1))
        }
    }

    /// Claude Code writes `procStart` from `LC_ALL=C TZ=UTC ps -o lstart= -p <pid>`: reading that
    /// back must give the probe's start time, to the second.
    @Test func procStartFromPsMatchesTheProbe() throws {
        try withSleepingChild { pid in
            let ps = Process()
            let output = Pipe()
            ps.executableURL = URL(fileURLWithPath: "/bin/ps")
            ps.arguments = ["-o", "lstart=", "-p", String(pid)]
            ps.environment = ["LC_ALL": "C", "TZ": "UTC"]
            ps.standardOutput = output
            try ps.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            ps.waitUntilExit()
            let lstart = String(decoding: data, as: UTF8.self)

            let recorded = try #require(ProcessStart.parseLstart(lstart), "ps printed \(lstart)")
            let started = try #require(probe.startTime(pid: pid))

            #expect(recorded.timeIntervalSince1970 == started.timeIntervalSince1970.rounded(.down))
            #expect(ProcessStart.matches(started, recorded: recorded))
        }
    }

    @Test func exitedChildHasNoStartTime() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try child.run()
        child.waitUntilExit()

        #expect(!probe.isAlive(pid: child.processIdentifier))
        #expect(probe.startTime(pid: child.processIdentifier) == nil)
    }

    @Test func aShellChildIsSeen() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        // A second command keeps the shell from replacing itself with `sleep`.
        child.arguments = ["-c", "sleep 30; :"]
        try child.run()
        defer {
            child.terminate()
            child.waitUntilExit()
        }

        #expect(probe.shellParents().contains(getpid()))
    }

    @Test(arguments: [0, -1, Int32.min, Int32.max] as [Int32])
    func invalidPidsHaveNoStartTime(_ pid: Int32) {
        #expect(probe.startTime(pid: pid) == nil)
        #expect(!probe.isAlive(pid: pid))
    }
}
