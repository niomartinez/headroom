import Darwin
import Foundation

public protocol ProcessProbing: Sendable {
    func isAlive(pid: Int32) -> Bool

    /// When the process that now holds `pid` started, or nil when that cannot be told (no such
    /// process, or the system would not say). A later start than a session's own means its pid was
    /// reused; nil leaves liveness to `isAlive` alone.
    func startTime(pid: Int32) -> Date?

    /// Pids that have a shell for a direct child: a Claude Code process still running a command (1.1 §14.11).
    func shellParents() -> Set<Int32>
}

extension ProcessProbing {
    /// Probes that cannot tell start times keep plain `isAlive` liveness.
    public func startTime(pid: Int32) -> Date? { nil }

    /// Probes that cannot read the process table see no running commands.
    public func shellParents() -> Set<Int32> { [] }
}

/// `kill(pid, 0) == 0 || errno == EPERM` (spec §2.2), and the start time from
/// `sysctl(KERN_PROC_PID)`, the same `p_starttime` that `ps -o lstart` prints.
public struct SystemProcessProbe: ProcessProbing {
    public init() {}

    public func isAlive(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    public func startTime(pid: Int32) -> Date? {
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
        let start = info.kp_proc.p_un.__p_starttime
        guard start.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }

    public func shellParents() -> Set<Int32> {
        ShellChildren.parents(in: SystemProcessTable())
    }
}
