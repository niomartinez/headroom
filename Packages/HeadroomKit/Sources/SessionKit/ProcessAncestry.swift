import Darwin
import Foundation

/// One process as `sysctl(KERN_PROC_*)` describes it: enough to walk from a session's pid up to the app it runs in
/// (1.1 §14.3, "Show in Terminal").
public struct ProcessEntry: Sendable, Equatable {
    public var pid: Int32
    /// The parent's pid (`kp_eproc.e_ppid`): 1 for a process launchd adopted, 0 for launchd itself.
    public var parent: Int32
    /// `p_comm`: the executable's name, cut to 16 bytes ("claude", "zsh", "iTermServer-3.6").
    public var command: String
    /// The controlling terminal's device name ("ttys009"), nil without one.
    public var tty: String?

    public init(pid: Int32, parent: Int32, command: String, tty: String? = nil) {
        self.pid = pid
        self.parent = parent
        self.command = command
        self.tty = tty
    }
}

/// The process table, read-only. Faked in tests; `SystemProcessTable` asks the kernel.
public protocol ProcessTableReading: Sendable {
    /// The process holding `pid`, or nil when there is none (or the system won't say).
    func entry(pid: Int32) -> ProcessEntry?
    /// Every process, or nil when the list can't be read (a sandbox may refuse it). Entries may leave `tty` out:
    /// naming every process's terminal costs a lookup each; ask `entry(pid:)` for one.
    func all() -> [ProcessEntry]?
    /// The process's current working directory, or nil when it can't be read.
    func workingDirectory(pid: Int32) -> String?
}

/// `sysctl(KERN_PROC_PID / KERN_PROC_ALL)` and `proc_pidinfo(PROC_PIDVNODEPATHINFO)`. Neither needs an
/// entitlement, and both work inside the App Sandbox (checked in a sandboxed probe app, 1.1 §14.3).
public struct SystemProcessTable: ProcessTableReading {
    public init() {}

    public func entry(pid: Int32) -> ProcessEntry? {
        // Pid 0 would describe the kernel.
        guard pid > 0 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        // A pid with no process succeeds with nothing written (size 0).
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0,
              size >= MemoryLayout<kinfo_proc>.size,
              info.kp_proc.p_pid == pid
        else { return nil }
        return Self.entry(info, namingTTY: true)
    }

    public func all() -> [ProcessEntry]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        // The list can grow between sizing and reading: retry with the new size a few times.
        for _ in 0..<4 {
            var size = 0
            guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
            // Room for processes started in between.
            size += size / 8
            let stride = MemoryLayout<kinfo_proc>.stride
            var processes = [kinfo_proc](repeating: kinfo_proc(), count: size / stride)
            let result = processes.withUnsafeMutableBytes { buffer in
                // The buffer's exact length, so the kernel never writes past it.
                size = buffer.count
                return sysctl(&mib, u_int(mib.count), buffer.baseAddress, &size, nil, 0)
            }
            if result != 0 {
                if errno == ENOMEM { continue }
                return nil
            }
            let count = size / stride
            guard count > 0 else { return nil }
            return processes.prefix(count).filter { $0.kp_proc.p_pid > 0 }.map { Self.entry($0, namingTTY: false) }
        }
        return nil
    }

    public func workingDirectory(pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    private static func entry(_ info: kinfo_proc, namingTTY: Bool) -> ProcessEntry {
        let command = withUnsafeBytes(of: info.kp_proc.p_comm) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return ProcessEntry(
            pid: info.kp_proc.p_pid, parent: info.kp_eproc.e_ppid, command: command,
            tty: namingTTY ? ttyName(info.kp_eproc.e_tdev) : nil
        )
    }

    /// "ttys009" for a terminal device; nil for none (`NODEV`) or one `devname` can't name.
    private static func ttyName(_ device: dev_t) -> String? {
        guard device != -1, let name = devname(device, S_IFCHR) else { return nil }
        let text = String(cString: name)
        return text.isEmpty || text == "??" ? nil : text
    }
}

/// Walks up the process tree (1.1 §14.3): from a session's pid to the app it runs in.
public enum ProcessAncestry {
    /// Deep enough for a shell in a multiplexer in an editor's terminal; a longer chain is not followed.
    public static let defaultLimit = 16

    /// `pid`'s process, then its parent, grandparent and so on: nearest first, at most `limit` entries. The walk
    /// stops before launchd (pid 1) and pid 0, at a process the table doesn't know (it exited, or the system won't
    /// say), and at a pid it has already seen (a table read while processes come and go can loop).
    public static func chain(
        from pid: Int32,
        in table: some ProcessTableReading,
        limit: Int = defaultLimit
    ) -> [ProcessEntry] {
        var chain: [ProcessEntry] = []
        var seen: Set<Int32> = []
        var next = pid
        while chain.count < limit, next > 1, seen.insert(next).inserted, let entry = table.entry(pid: next) {
            chain.append(entry)
            next = entry.parent
        }
        return chain
    }
}

/// 1.1 §14.11: Claude Code runs each Bash tool command, background task and monitor in a shell it spawns itself, so a
/// session's process has a shell child exactly while one of them runs. MCP servers are `node`, `npm`, `uv`, … children.
public enum ShellChildren {
    /// `p_comm` of the shells a command can run in (the user's shell).
    static let shells: Set<String> = ["bash", "zsh", "sh", "fish", "dash", "ksh", "tcsh", "csh"]

    /// The parent of every shell in `table`; empty when the table can't be read.
    public static func parents(in table: some ProcessTableReading) -> Set<Int32> {
        Set((table.all() ?? []).filter { shells.contains($0.command) }.map(\.parent))
    }
}
