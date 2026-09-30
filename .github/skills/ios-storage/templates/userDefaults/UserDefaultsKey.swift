import Foundation

/// A typed preference key. Declare keys as constants in the consumer (e.g. a domain client),
/// not as string literals at call sites:
///
/// ```swift
/// extension UserDefaultsKey where Value == Bool {
///     static let hasSeenOnboarding = Self("hasSeenOnboarding", default: false)
/// }
/// extension UserDefaultsKey where Value == SortOrder {
///     static let sortOrder = Self.codable("sortOrder", default: .newestFirst)
/// }
/// ```
public struct UserDefaultsKey<Value: Sendable>: Sendable {
    public let name: String
    public let defaultValue: Value
    let kind: UserDefaultsValue.Kind
    let encode: @Sendable (Value) throws -> UserDefaultsValue
    let decode: @Sendable (UserDefaultsValue) -> Value?
}

public extension UserDefaultsKey where Value: UserDefaultsPrimitive {
    /// A plist primitive, stored natively (readable by `@AppStorage` and Settings bundles).
    init(_ name: String, default defaultValue: Value) {
        self.init(
            name: name,
            defaultValue: defaultValue,
            kind: Value.kind,
            encode: { $0.userDefaultsValue },
            decode: { Value(userDefaultsValue: $0) }
        )
    }
}

public extension UserDefaultsKey where Value: Codable {
    /// A small `Codable` value, stored as JSON `Data`. A value that no longer decodes (e.g. after a
    /// model change) reads as `defaultValue`.
    static func codable(_ name: String, default defaultValue: Value) -> Self {
        Self(
            name: name,
            defaultValue: defaultValue,
            kind: .data,
            encode: { .data(try JSONEncoder().encode($0)) },
            decode: { stored in
                guard case let .data(data) = stored else { return nil }
                return try? JSONDecoder().decode(Value.self, from: data)
            }
        )
    }
}

/// A property-list value as stored in `UserDefaults`.
public enum UserDefaultsValue: Equatable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case data(Data)
    case date(Date)

    public enum Kind: Equatable, Sendable {
        case bool, int, double, string, data, date
    }

    public var kind: Kind {
        switch self {
        case .bool: .bool
        case .int: .int
        case .double: .double
        case .string: .string
        case .data: .data
        case .date: .date
        }
    }
}

/// Types stored natively as plist primitives.
public protocol UserDefaultsPrimitive: Sendable {
    static var kind: UserDefaultsValue.Kind { get }
    var userDefaultsValue: UserDefaultsValue { get }
    init?(userDefaultsValue: UserDefaultsValue)
}

extension Bool: UserDefaultsPrimitive {
    public static var kind: UserDefaultsValue.Kind { .bool }
    public var userDefaultsValue: UserDefaultsValue { .bool(self) }
    public init?(userDefaultsValue: UserDefaultsValue) {
        guard case let .bool(value) = userDefaultsValue else { return nil }
        self = value
    }
}

extension Int: UserDefaultsPrimitive {
    public static var kind: UserDefaultsValue.Kind { .int }
    public var userDefaultsValue: UserDefaultsValue { .int(self) }
    public init?(userDefaultsValue: UserDefaultsValue) {
        guard case let .int(value) = userDefaultsValue else { return nil }
        self = value
    }
}

extension Double: UserDefaultsPrimitive {
    public static var kind: UserDefaultsValue.Kind { .double }
    public var userDefaultsValue: UserDefaultsValue { .double(self) }
    public init?(userDefaultsValue: UserDefaultsValue) {
        guard case let .double(value) = userDefaultsValue else { return nil }
        self = value
    }
}

extension String: UserDefaultsPrimitive {
    public static var kind: UserDefaultsValue.Kind { .string }
    public var userDefaultsValue: UserDefaultsValue { .string(self) }
    public init?(userDefaultsValue: UserDefaultsValue) {
        guard case let .string(value) = userDefaultsValue else { return nil }
        self = value
    }
}

extension Data: UserDefaultsPrimitive {
    public static var kind: UserDefaultsValue.Kind { .data }
    public var userDefaultsValue: UserDefaultsValue { .data(self) }
    public init?(userDefaultsValue: UserDefaultsValue) {
        guard case let .data(value) = userDefaultsValue else { return nil }
        self = value
    }
}

extension Date: UserDefaultsPrimitive {
    public static var kind: UserDefaultsValue.Kind { .date }
    public var userDefaultsValue: UserDefaultsValue { .date(self) }
    public init?(userDefaultsValue: UserDefaultsValue) {
        guard case let .date(value) = userDefaultsValue else { return nil }
        self = value
    }
}
