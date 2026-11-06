import Testing
@testable import ContextKit

@Suite("BoundedCache")
struct BoundedCacheTests {
    @Test func storesUpdatesAndRemoves() {
        let cache = BoundedCache<Int>(limit: 4)
        cache["a"] = 1
        cache["a"] = 2
        #expect(cache["a"] == 2)
        cache["a"] = nil
        #expect(cache["a"] == nil)
    }

    @Test func startsOverWhenANewKeyWouldExceedTheLimit() {
        let cache = BoundedCache<Int>(limit: 2)
        cache["a"] = 1
        cache["b"] = 2
        cache["b"] = 3
        #expect(cache["a"] == 1, "updating an existing key keeps the others")
        cache["c"] = 4
        #expect(cache["a"] == nil)
        #expect(cache["b"] == nil)
        #expect(cache["c"] == 4)
    }
}
