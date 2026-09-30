import Dependencies
import DependenciesMacros
import Foundation

/// Typed storage for small, **non-secret** preferences (flags, last-selected tab, onboarding seen).
/// Secrets (tokens, credentials) go in `KeychainClient`, never here.
///
/// The endpoints are raw and keyed by name; consumers use the typed `value(_:)` / `set(_:for:)` /
/// `remove(_:)` helpers with `UserDefaultsKey` constants. Endpoints are sync: `UserDefaults` is an
/// in-process cache and is thread-safe.
@DependencyClient
public struct UserDefaultsClient: Sendable {
    /// Returns `nil` if the key is missing or the stored object isn't of the expected kind.
    public var value: @Sendable (_ key: String, _ kind: UserDefaultsValue.Kind) -> UserDefaultsValue? = { _, _ in nil }
    public var setValue: @Sendable (_ value: UserDefaultsValue, _ key: String) -> Void
    public var remove: @Sendable (_ key: String) -> Void
}

public extension UserDefaultsClient {
    /// The stored value, or `key.defaultValue` if it's missing or can't be decoded.
    func value<Value>(_ key: UserDefaultsKey<Value>) -> Value {
        value(key.name, key.kind).flatMap(key.decode) ?? key.defaultValue
    }

    /// Throws only if a `.codable` key fails to encode.
    func set<Value>(_ value: Value, for key: UserDefaultsKey<Value>) throws {
        setValue(try key.encode(value), key.name)
    }

    /// Removes the stored value; `value(_:)` returns the default afterwards.
    func remove<Value>(_ key: UserDefaultsKey<Value>) {
        remove(key.name)
    }
}

extension UserDefaultsClient: DependencyKey {
    // >>> config
    public static let liveValue = UserDefaultsClient.live(.standard)
    // or, to share with app extensions: UserDefaultsClient.live(suiteName: "__SuiteName__")
    // <<< config

    /// Unimplemented. Tests that exercise preferences use `.inMemory()`.
    public static let testValue = UserDefaultsClient()

    /// Previews must never write to the real defaults.
    public static let previewValue = UserDefaultsClient.inMemory()
}

public extension DependencyValues {
    var userDefaultsClient: UserDefaultsClient {
        get { self[UserDefaultsClient.self] }
        set { self[UserDefaultsClient.self] = newValue }
    }
}

public extension UserDefaultsClient {
    /// A working, isolated store for tests and previews: `$0.userDefaultsClient = .inMemory()`.
    static func inMemory(_ initial: [String: UserDefaultsValue] = [:]) -> Self {
        let storage = LockIsolated(initial)
        return Self(
            value: { key, kind in storage.value[key].flatMap { $0.kind == kind ? $0 : nil } },
            setValue: { value, key in storage.withValue { $0[key] = value } },
            remove: { key in storage.withValue { $0[key] = nil } }
        )
    }
}
