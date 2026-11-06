import os

/// A thread-safe string-keyed cache. When it would grow past `limit` entries it starts over,
/// which keeps a long-running app from accumulating entries for sessions that ended long ago.
final class BoundedCache<Value: Sendable>: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [String: Value]())
    private let limit: Int

    init(limit: Int = 512) {
        self.limit = limit
    }

    subscript(key: String) -> Value? {
        get { storage.withLock { $0[key] } }
        set {
            storage.withLock { entries in
                if newValue != nil, entries[key] == nil, entries.count >= limit {
                    entries.removeAll()
                }
                entries[key] = newValue
            }
        }
    }
}

/// A thread-safe counter, used to observe cache behaviour in tests.
final class Counter: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: 0)

    var value: Int { storage.withLock { $0 } }

    func increment() {
        storage.withLock { $0 += 1 }
    }
}
