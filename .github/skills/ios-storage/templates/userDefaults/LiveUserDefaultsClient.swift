import Dependencies
import Foundation

extension UserDefaultsClient {
    /// Backed by a `UserDefaults` instance: `.standard`, or an app group suite.
    public static func live(_ defaults: UserDefaults) -> Self {
        // `UserDefaults` is documented as thread-safe but isn't annotated `Sendable` in the SDK.
        let defaults = UncheckedSendable(defaults)
        return Self(
            value: { key, kind in LiveUserDefaults.read(defaults.value, key, kind) },
            setValue: { value, key in LiveUserDefaults.write(defaults.value, value, key) },
            remove: { key in defaults.value.removeObject(forKey: key) }
        )
    }

    /// An app group suite shared with extensions (`group.<id>`, listed in the App Groups
    /// capability of every target that shares it).
    public static func live(suiteName: String) -> Self {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Invalid UserDefaults suite name")
        }
        return live(defaults)
    }
}

/// Pure mapping between `UserDefaults` objects and `UserDefaultsValue`, tested against a
/// throwaway suite.
enum LiveUserDefaults {
    static func read(_ defaults: UserDefaults, _ key: String, _ kind: UserDefaultsValue.Kind) -> UserDefaultsValue? {
        guard let object = defaults.object(forKey: key) else { return nil }
        switch kind {
        case .bool: return (object as? Bool).map(UserDefaultsValue.bool)
        case .int: return (object as? Int).map(UserDefaultsValue.int)
        case .double: return (object as? Double).map(UserDefaultsValue.double)
        case .string: return (object as? String).map(UserDefaultsValue.string)
        case .data: return (object as? Data).map(UserDefaultsValue.data)
        case .date: return (object as? Date).map(UserDefaultsValue.date)
        }
    }

    static func write(_ defaults: UserDefaults, _ value: UserDefaultsValue, _ key: String) {
        switch value {
        case let .bool(value): defaults.set(value, forKey: key)
        case let .int(value): defaults.set(value, forKey: key)
        case let .double(value): defaults.set(value, forKey: key)
        case let .string(value): defaults.set(value, forKey: key)
        case let .data(value): defaults.set(value, forKey: key)
        case let .date(value): defaults.set(value, forKey: key)
        }
    }
}
