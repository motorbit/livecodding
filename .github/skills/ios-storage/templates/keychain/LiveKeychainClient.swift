import Foundation
import Security

/// Where and how items are stored. Decide it once per app. Changing it later strands existing items.
public struct KeychainConfiguration: Equatable, Sendable {
    public var service: String
    public var accessibility: KeychainAccessibility
    /// `nil` = the app's default access group. Set `"<TeamID>.<group>"` to share items with other
    /// apps/extensions that list the same group in their Keychain Sharing entitlement.
    public var accessGroup: String?

    public init(service: String, accessibility: KeychainAccessibility, accessGroup: String? = nil) {
        self.service = service
        self.accessibility = accessibility
        self.accessGroup = accessGroup
    }

    // >>> config
    public static let `default` = KeychainConfiguration(
        service: "__BundleID__.keychain",
        accessibility: .__accessibility__,
        accessGroup: nil // or "__AccessGroup__"
    )
    // <<< config
}

/// When the item is readable. The `…ThisDeviceOnly` variants are excluded from backups and
/// device migration.
public enum KeychainAccessibility: Equatable, Sendable {
    /// Only while unlocked. Strictest; foreground-only secrets.
    case whenUnlockedThisDeviceOnly
    /// After the first unlock since boot. Needed for background refresh, push handling, etc.
    case afterFirstUnlockThisDeviceOnly
    /// Only when a device passcode is set; the item is deleted if the passcode is removed.
    case whenPasscodeSetThisDeviceOnly

    var secValue: CFString {
        switch self {
        case .whenUnlockedThisDeviceOnly: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .afterFirstUnlockThisDeviceOnly: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenPasscodeSetThisDeviceOnly: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        }
    }
}

extension KeychainClient {
    static func live(configuration: KeychainConfiguration) -> Self {
        let store = LiveKeychainStore(configuration: configuration)
        return Self(
            data: { key in try await store.data(key) },
            setData: { data, key in try await store.set(data, key) },
            delete: { key in try await store.delete(key) },
            deleteAll: { try await store.deleteAll() }
        )
    }
}

struct LiveKeychainStore: Sendable {
    let configuration: KeychainConfiguration

    @concurrent
    func data(_ key: String) async throws -> Data? {
        var query = KeychainQuery.item(key, configuration)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError.unexpectedStatus(status)
        }
    }

    @concurrent
    func set(_ data: Data, _ key: String) async throws {
        let query = KeychainQuery.item(key, configuration)
        let attributes = KeychainQuery.writeAttributes(data, configuration)
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            let addStatus = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    @concurrent
    func delete(_ key: String) async throws {
        try Self.check(SecItemDelete(KeychainQuery.item(key, configuration) as CFDictionary))
    }

    @concurrent
    func deleteAll() async throws {
        try Self.check(SecItemDelete(KeychainQuery.service(configuration) as CFDictionary))
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

/// Pure query builders, unit-tested without touching the keychain.
enum KeychainQuery {
    static func service(_ configuration: KeychainConfiguration) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.service,
        ]
        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    static func item(_ key: String, _ configuration: KeychainConfiguration) -> [String: Any] {
        var query = service(configuration)
        query[kSecAttrAccount as String] = key
        return query
    }

    static func writeAttributes(_ data: Data, _ configuration: KeychainConfiguration) -> [String: Any] {
        [
            kSecValueData as String: data,
            kSecAttrAccessible as String: configuration.accessibility.secValue,
        ]
    }
}
