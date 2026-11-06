import Foundation

/// The Claude desktop app, looked up through Launch Services (spec §2.1, `AccessState.desktopAppInstalled`).
enum ClaudeDesktopApp {
    /// Verified on the developer's Mac (`/Applications/Claude.app`), 2026-09-24.
    static let bundleIdentifier = "com.anthropic.claudefordesktop"
    /// The app can be installed or removed while Headroom runs; the 2 s poll looks it up again
    /// this often, and Settings looks it up whenever its window comes forward.
    static let recheckInterval: TimeInterval = 60
}

/// The Codex app (ChatGPT.app's Codex, bundle id `com.openai.codex`, 1.1 §3.1): installed counts toward "Codex
/// installed" (the Codex offer), running toward Codex session liveness (§3.5).
enum CodexApp {
    static let bundleIdentifier = "com.openai.codex"
    static let recheckInterval: TimeInterval = ClaudeDesktopApp.recheckInterval
}

/// A yes/no answer that costs a system call to look up, re-checked at most once per `interval`
/// instead of on every 2 s poll.
struct PeriodicCheck {
    let interval: TimeInterval
    private(set) var cached: Bool?
    private var checkedAt: Date?

    init(interval: TimeInterval) {
        self.interval = interval
    }

    /// The cached answer while it's younger than `interval`, otherwise a fresh `lookup()`.
    mutating func value(at now: Date, lookup: () -> Bool) -> Bool {
        if let current = current(at: now) { return current }
        let fresh = lookup()
        record(fresh, at: now)
        return fresh
    }

    /// The cached answer while it's younger than `interval`; nil when a lookup is due. With
    /// `record(_:at:)`, lets the lookup run elsewhere (the poll's worker, off the main thread).
    func current(at now: Date) -> Bool? {
        guard let cached, let checkedAt else { return nil }
        let age = now.timeIntervalSince(checkedAt)
        // A negative age means the clock was set back: look up again rather than trust it.
        return age >= 0 && age < interval ? cached : nil
    }

    /// Keeps `value`, looked up at `now`, for the next `interval`.
    mutating func record(_ value: Bool, at now: Date) {
        cached = value
        checkedAt = now
    }

    /// The next `value(at:lookup:)` looks up again.
    mutating func invalidate() {
        checkedAt = nil
    }
}
