import Foundation
import SessionKit

/// A unique scratch directory under the system temp dir, removed by `remove()`.
struct TempDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @discardableResult
    func write(_ name: String, _ contents: String) throws -> URL {
        let file = url.appendingPathComponent(name)
        try Data(contents.utf8).write(to: file)
        return file
    }

    func write(_ name: String, data: Data) throws {
        try data.write(to: url.appendingPathComponent(name))
    }

    func remove() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }
}

/// A `ProcessProbing` whose live pids, and the start times it can tell, are fixed by the test.
struct FakeProcessProbe: ProcessProbing {
    var alive: Set<Int32>
    var startTimes: [Int32: Date]

    init(alive: Set<Int32> = [], startTimes: [Int32: Date] = [:]) {
        self.alive = alive
        self.startTimes = startTimes
    }

    func isAlive(pid: Int32) -> Bool {
        alive.contains(pid)
    }

    func startTime(pid: Int32) -> Date? {
        alive.contains(pid) ? startTimes[pid] : nil
    }
}

/// A probe that only implements `isAlive`, like conformers written before `startTime(pid:)` existed.
struct LivenessOnlyProbe: ProcessProbing {
    var alive: Set<Int32>

    func isAlive(pid: Int32) -> Bool {
        alive.contains(pid)
    }
}

/// A fixed "now" for merge tests: 2026-09-24 12:00:00 UTC.
let testNow = Date(timeIntervalSince1970: 1_790_251_200)

func minutes(_ value: Double) -> TimeInterval { value * 60 }
