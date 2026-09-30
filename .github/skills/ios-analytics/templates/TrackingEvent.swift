/// A product-analytics event. Each feature defines its own `enum XxxEvent: TrackingEvent` in its
/// module. Conforming enums stay nonisolated even in MainActor-default modules, because the
/// protocol refines `Sendable` (SE-0466).
///
/// Naming:
/// - `name` is snake_case `<object>_<action>` in the past tense: `sign_in_completed`,
///   `item_added_to_list`, `screen_viewed`. At most 40 characters, `[a-z0-9_]` only.
/// - Parameter keys are snake_case nouns: `duration_ms`, `source`, `item_count`.
/// - Never send PII (emails, names, ids from the user's world, free text) or raw error messages;
///   send categories/codes and pass anything textual through `AnalyticsSanitizer`.
public protocol TrackingEvent: Sendable {
    var name: String { get }
    var parameters: [String: AnalyticsValue] { get }
}

public extension TrackingEvent {
    var parameters: [String: AnalyticsValue] { [:] }
}

/// The parameter values every provider can represent. It's typed, so `Any` never reaches a
/// vendor SDK.
public enum AnalyticsValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}

extension AnalyticsValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

/// Validates event and parameter names against the naming rules above.
public enum TrackingEventName {
    public static func isValid(_ name: String) -> Bool {
        !name.isEmpty
            && name.count <= 40
            && name.first?.isLetter == true
            && name.allSatisfy { ($0.isLowercase && $0.isASCII) || $0.isNumber || $0 == "_" }
    }
}
