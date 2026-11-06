import CopilotKit
import Foundation
import Testing

/// Headroom's Keychain item for its GitHub tokens (1.1 §4.3). Each test uses a service name of its own, never the
/// app's (`com.niomartinez.headroom.github`), and deletes what it wrote, before and after. A test runner may not use
/// the data-protection keychain, so these usually exercise the login keychain fallback.
@Suite(.serialized) struct KeychainTokenStoreTests {
    /// A store for a fixed test service, so that an interrupted run's item is deleted by the next run.
    private func makeStore(_ name: String) -> KeychainTokenStore {
        KeychainTokenStore(service: "com.niomartinez.headroom.github.tests.\(name)", account: "default")
    }

    /// Runs `body` with an empty test store, then deletes its item whatever happened.
    private func withStore(_ name: String, _ body: (KeychainTokenStore) async throws -> Void) async throws {
        let store = makeStore(name)
        try await store.delete()
        do {
            try await body(store)
        } catch {
            try? await store.delete()
            throw error
        }
        try await store.delete()
    }

    private func pair(_ suffix: String) -> TokenPair {
        TokenPair(
            access: "ghu_FAKE\(suffix)", refresh: "ghr_FAKE\(suffix)",
            accessExpiresAt: Date(timeIntervalSince1970: 1_790_000_000),
            refreshExpiresAt: Date(timeIntervalSince1970: 1_805_000_000)
        )
    }

    @Test func theAppUsesItsOwnItem() {
        #expect(KeychainTokenStore.defaultService == "com.niomartinez.headroom.github")
        #expect(KeychainTokenStore.defaultAccount == "default")
        let store = KeychainTokenStore()
        #expect(store.service == "com.niomartinez.headroom.github")
        #expect(store.account == "default")
    }

    @Test func aPairIsSavedReplacedAndDeleted() async throws {
        try await withStore("roundtrip") { store in
            try await savedReplacedAndDeleted(store)
        }
    }

    private func savedReplacedAndDeleted(_ store: KeychainTokenStore) async throws {
        #expect(try await store.load() == nil)

        try await store.save(pair("A"))
        #expect(try await store.load() == pair("A"))

        // Both tokens rotate on a refresh: the one item is replaced.
        try await store.save(pair("B"))
        #expect(try await store.load() == pair("B"))

        try await store.delete()
        #expect(try await store.load() == nil)
        // Deleting what isn't there is fine (Disconnect twice).
        try await store.delete()
    }

    @Test func itemsOfOtherServicesAreNotSeen() async throws {
        try await withStore("first") { first in
            try await withStore("second") { second in
                try await first.save(pair("C"))
                #expect(try await second.load() == nil)
                #expect(try await first.load() == pair("C"))
            }
        }
    }

    @Test func errorsNameOnlyTheStatus() {
        let error = KeychainError.status(-25300)
        #expect(error.description.hasPrefix("Keychain error -25300"))
        #expect(!KeychainError.unexpectedItem.description.contains("ghu_"))
    }
}
