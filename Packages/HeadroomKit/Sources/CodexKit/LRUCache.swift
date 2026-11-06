/// A small least-recently-used cache: at `capacity`, adding a key evicts the entry used longest ago. Linear
/// eviction, which is fine at the 64 entries CodexKit keeps (1.1 §3.3). Not thread-safe.
struct LRUCache<Key: Hashable, Value> {
    let capacity: Int
    private var entries: [Key: (value: Value, used: UInt64)] = [:]
    private var clock: UInt64 = 0

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    var count: Int { entries.count }

    /// The value, marked as just used.
    mutating func value(_ key: Key) -> Value? {
        guard let entry = entries[key] else { return nil }
        clock += 1
        entries[key] = (entry.value, clock)
        return entry.value
    }

    mutating func set(_ key: Key, _ value: Value) {
        clock += 1
        if entries[key] == nil, entries.count >= capacity,
           let oldest = entries.min(by: { $0.value.used < $1.value.used })?.key {
            entries[oldest] = nil
        }
        entries[key] = (value, clock)
    }

    mutating func remove(_ key: Key) {
        entries[key] = nil
    }

    mutating func removeAll() {
        entries.removeAll()
    }
}
