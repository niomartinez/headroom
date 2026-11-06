import Darwin
import Foundation
import Testing
@testable import SessionKit

/// A process table fixed by the test.
private struct FakeProcessTable: ProcessTableReading {
    var entries: [Int32: ProcessEntry]
    var directories: [Int32: String] = [:]

    init(_ entries: [ProcessEntry], directories: [Int32: String] = [:]) {
        self.entries = Dictionary(uniqueKeysWithValues: entries.map { ($0.pid, $0) })
        self.directories = directories
    }

    func entry(pid: Int32) -> ProcessEntry? { entries[pid] }
    func all() -> [ProcessEntry]? { entries.values.sorted { $0.pid < $1.pid } }
    func workingDirectory(pid: Int32) -> String? { directories[pid] }
}

/// 1.1 §14.3: from a session's pid up to the app it runs in.
@Suite struct ProcessAncestryTests {
    @Test func walksNearestFirstAndStopsBeforeLaunchd() {
        let table = FakeProcessTable([
            ProcessEntry(pid: 1, parent: 0, command: "launchd"),
            ProcessEntry(pid: 500, parent: 1, command: "Terminal"),
            ProcessEntry(pid: 600, parent: 500, command: "login", tty: "ttys009"),
            ProcessEntry(pid: 610, parent: 600, command: "zsh", tty: "ttys009"),
            ProcessEntry(pid: 700, parent: 610, command: "claude", tty: "ttys009"),
        ])

        let chain = ProcessAncestry.chain(from: 700, in: table)

        #expect(chain.map(\.command) == ["claude", "zsh", "login", "Terminal"])
        #expect(chain.first?.tty == "ttys009")
    }

    @Test func aMissingAncestorEndsTheChain() {
        let table = FakeProcessTable([
            ProcessEntry(pid: 610, parent: 600, command: "zsh"),
            ProcessEntry(pid: 700, parent: 610, command: "claude"),
        ])

        #expect(ProcessAncestry.chain(from: 700, in: table).map(\.pid) == [700, 610])
        #expect(ProcessAncestry.chain(from: 999, in: table).isEmpty)
    }

    @Test func aLoopIsFollowedOnce() {
        let table = FakeProcessTable([
            ProcessEntry(pid: 10, parent: 20, command: "a"),
            ProcessEntry(pid: 20, parent: 30, command: "b"),
            ProcessEntry(pid: 30, parent: 10, command: "c"),
        ])

        #expect(ProcessAncestry.chain(from: 10, in: table).map(\.pid) == [10, 20, 30])
    }

    @Test func aSelfParentedProcessIsListedOnce() {
        let table = FakeProcessTable([ProcessEntry(pid: 10, parent: 10, command: "odd")])

        #expect(ProcessAncestry.chain(from: 10, in: table).map(\.pid) == [10])
    }

    @Test func stopsAtTheLimit() {
        let table = FakeProcessTable((2...40).map { ProcessEntry(pid: Int32($0), parent: Int32($0 - 1), command: "p\($0)") })

        #expect(ProcessAncestry.chain(from: 40, in: table).count == ProcessAncestry.defaultLimit)
        #expect(ProcessAncestry.chain(from: 40, in: table, limit: 3).map(\.pid) == [40, 39, 38])
        // Down to pid 2: launchd (1) is never included.
        #expect(ProcessAncestry.chain(from: 5, in: table).map(\.pid) == [5, 4, 3, 2])
    }

    @Test func pidsAtOrBelowLaunchdHaveNoChain() {
        let table = FakeProcessTable([
            ProcessEntry(pid: 1, parent: 0, command: "launchd"),
            ProcessEntry(pid: 0, parent: 0, command: "kernel_task"),
        ])

        #expect(ProcessAncestry.chain(from: 1, in: table).isEmpty)
        #expect(ProcessAncestry.chain(from: 0, in: table).isEmpty)
        #expect(ProcessAncestry.chain(from: -5, in: table).isEmpty)
    }
}

/// The real table, on this test process: read-only, and nothing about it is kept.
@Suite struct SystemProcessTableTests {
    @Test func describesThisProcessAndItsParent() throws {
        let table = SystemProcessTable()
        let me = try #require(table.entry(pid: getpid()))

        #expect(me.pid == getpid())
        #expect(me.parent == getppid())
        #expect(!me.command.isEmpty)
        #expect(ProcessAncestry.chain(from: getpid(), in: table).first == me)
    }

    @Test func noProcessNoEntry() {
        let table = SystemProcessTable()
        #expect(table.entry(pid: 0) == nil)
        #expect(table.entry(pid: -1) == nil)
        #expect(table.workingDirectory(pid: 0) == nil)
    }

    @Test func workingDirectoryOfThisProcess() throws {
        let table = SystemProcessTable()
        let directory = try #require(table.workingDirectory(pid: getpid()))
        let expected = FileManager.default.currentDirectoryPath
        #expect(URL(fileURLWithPath: directory).resolvingSymlinksInPath() == URL(fileURLWithPath: expected).resolvingSymlinksInPath())
    }

    @Test func listsThisProcess() throws {
        let all = try #require(SystemProcessTable().all())
        #expect(all.contains { $0.pid == getpid() })
        #expect(all.allSatisfy { $0.pid > 0 })
        // The whole list names no terminals (a lookup per process); `entry(pid:)` does.
        #expect(all.allSatisfy { $0.tty == nil })
    }
}

/// 1.1 §14.11: a session's process with a shell child is running a command.
@Suite struct ShellChildrenTests {
    @Test func parentsOfShellsOnly() {
        let table = FakeProcessTable([
            ProcessEntry(pid: 700, parent: 1, command: "claude"),
            ProcessEntry(pid: 701, parent: 700, command: "npm"),
            ProcessEntry(pid: 702, parent: 700, command: "node"),
            ProcessEntry(pid: 800, parent: 1, command: "claude"),
            ProcessEntry(pid: 801, parent: 800, command: "bash"),
            ProcessEntry(pid: 900, parent: 1, command: "claude"),
            ProcessEntry(pid: 901, parent: 900, command: "zsh"),
        ])

        #expect(ShellChildren.parents(in: table) == [800, 900])
    }

    @Test func anUnreadableTableHasNone() {
        struct Unreadable: ProcessTableReading {
            func entry(pid: Int32) -> ProcessEntry? { nil }
            func all() -> [ProcessEntry]? { nil }
            func workingDirectory(pid: Int32) -> String? { nil }
        }
        #expect(ShellChildren.parents(in: Unreadable()).isEmpty)
    }
}
