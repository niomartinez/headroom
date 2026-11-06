import Darwin

/// The names (`p_comm`, at most 16 bytes) of every process `sysctl(KERN_PROC_ALL)` returns, or nil when the list
/// can't be read (the sandbox may deny it, live check L4).
enum ProcessList {
    static func commandNames() -> [String]? {
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
            return processes.prefix(count).map { process in
                withUnsafeBytes(of: process.kp_proc.p_comm) { raw in
                    let bytes = raw.prefix { $0 != 0 }
                    return String(decoding: bytes, as: UTF8.self)
                }
            }
        }
        return nil
    }

    /// Whether `names` has a process named exactly `codex`: the CLI, or the one the Codex app runs (1.1 §3.5).
    static func containsCodex(_ names: [String]) -> Bool {
        names.contains("codex")
    }
}
