import Dependencies
import DependenciesMacros
import Foundation

/// Secure storage for small secrets as generic-password items (`kSecClassGenericPassword`),
/// addressed by `service` (from `KeychainConfiguration`) and `key` (account).
///
/// Endpoints are async: SecItem calls can block (e.g. while the device is still locked after
/// boot), so the live implementation runs them `@concurrent`, off the caller's actor.
@DependencyClient
public struct KeychainClient: Sendable {
    /// Returns `nil` if there's no item for `key`.
    public var data: @Sendable (_ key: String) async throws -> Data?
    /// Adds or updates (upsert).
    public var setData: @Sendable (_ data: Data, _ key: String) async throws -> Void
    /// No-op if there's no item for `key`.
    public var delete: @Sendable (_ key: String) async throws -> Void
    /// Removes every item of this service (e.g. on sign-out or an environment switch).
    public var deleteAll: @Sendable () async throws -> Void
}

public extension KeychainClient {
    func string(_ key: String) async throws -> String? {
        try await data(key).map { String(decoding: $0, as: UTF8.self) }
    }

    func setString(_ value: String, _ key: String) async throws {
        try await setData(Data(value.utf8), key)
    }
}

public enum KeychainError: Error, Equatable, Sendable {
    /// A raw `OSStatus`, e.g. -25308 (interaction not allowed: device locked) or
    /// -34018 (missing entitlement: running without a host app).
    case unexpectedStatus(Int32)
}

extension KeychainClient: DependencyKey {
    public static let liveValue = KeychainClient.live(configuration: .default)

    /// Unimplemented. Tests that exercise storage use `.inMemory()`.
    public static let testValue = KeychainClient()

    /// Previews must never touch the real keychain.
    public static let previewValue = KeychainClient.inMemory()
}

public extension DependencyValues {
    var keychainClient: KeychainClient {
        get { self[KeychainClient.self] }
        set { self[KeychainClient.self] = newValue }
    }
}

public extension KeychainClient {
    /// A working, isolated store for tests and previews: `$0.keychainClient = .inMemory(["token": …])`.
    static func inMemory(_ initial: [String: Data] = [:]) -> Self {
        let storage = LockIsolated(initial)
        return Self(
            data: { key in storage.value[key] },
            setData: { data, key in storage.withValue { $0[key] = data } },
            delete: { key in storage.withValue { $0[key] = nil } },
            deleteAll: { storage.setValue([:]) }
        )
    }
}
