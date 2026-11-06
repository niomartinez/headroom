import CopilotKit
import Foundation
import Security

/// Headroom's own Keychain item for its GitHub tokens (1.1 §4.3): a generic password, service
/// `com.niomartinez.headroom.github`, account `default`, holding `TokenPair`'s JSON
/// (`{"access":…,"refresh":…,"accessExpiresAt":…,"refreshExpiresAt":…}`). Never synchronized. Only `CopilotService`
/// uses it; the widget never does.
///
/// The data-protection keychain comes first (`kSecUseDataProtectionKeychain`, accessible after first unlock, this
/// device only). A build that may not use it (ad-hoc signed: no application identifier, `errSecMissingEntitlement`,
/// -34018, on writes) keeps the item in the login keychain instead [Apple TN3137]; reads and deletes look in both.
/// Errors carry only a status code, never a token.
struct KeychainTokenStore: TokenStore {
    static let defaultService = "com.niomartinez.headroom.github"
    static let defaultAccount = "default"

    let service: String
    let account: String

    /// Tests pass a service name of their own, and delete what they wrote.
    init(service: String = KeychainTokenStore.defaultService, account: String = KeychainTokenStore.defaultAccount) {
        self.service = service
        self.account = account
    }

    /// The data-protection keychain's item, else the login keychain's: a process that may not use the former answers
    /// "not found" there (and "missing entitlement" only when writing), so both are asked.
    func load() async throws -> TokenPair? {
        for dataProtection in [true, false] {
            var query = query(dataProtection: dataProtection)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            switch status {
            case errSecSuccess:
                guard let data = result as? Data else { throw KeychainError.unexpectedItem }
                do {
                    return try JSONDecoder().decode(TokenPair.self, from: data)
                } catch {
                    // Never the decoder's error: it could quote the item.
                    throw KeychainError.unexpectedItem
                }
            case errSecItemNotFound, errSecMissingEntitlement:
                continue
            default:
                throw KeychainError.status(status)
            }
        }
        return nil
    }

    /// Replaces the pair in one step: an update of the one item, or its creation.
    func save(_ pair: TokenPair) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(pair)
        try inPreferredKeychain { dataProtection in
            let query = query(dataProtection: dataProtection)
            var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = query
                item[kSecValueData as String] = data
                if dataProtection {
                    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                }
                status = SecItemAdd(item as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw KeychainError.status(status) }
        }
    }

    /// Deletes the item wherever it is.
    func delete() async throws {
        for dataProtection in [true, false] {
            let status = SecItemDelete(query(dataProtection: dataProtection) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound || status == errSecMissingEntitlement else {
                throw KeychainError.status(status)
            }
        }
    }

    /// The item, in the data-protection keychain or the login keychain.
    private func query(dataProtection: Bool) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: dataProtection,
        ]
    }

    /// Runs `body` against the data-protection keychain, and against the login keychain when this build may not write
    /// to that one.
    private func inPreferredKeychain<Value>(_ body: (_ dataProtection: Bool) throws -> Value) throws -> Value {
        do {
            return try body(true)
        } catch KeychainError.status(errSecMissingEntitlement) {
            return try body(false)
        }
    }
}

/// A Keychain failure: the status only.
enum KeychainError: Error, Equatable, CustomStringConvertible {
    case status(OSStatus)
    /// The item isn't a token pair Headroom wrote.
    case unexpectedItem

    var description: String {
        switch self {
        case let .status(status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
            return "Keychain error \(status): \(message)"
        case .unexpectedItem:
            return "The Keychain item isn't one Headroom wrote"
        }
    }
}
