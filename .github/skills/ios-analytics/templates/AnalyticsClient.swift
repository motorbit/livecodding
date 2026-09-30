import Dependencies
import DependenciesMacros
import Logging

/// Product analytics entry point. It's vendor-agnostic: the live value fans out to
/// `AnalyticsProvider`s. Features depend on this module only for `TrackingEvent` and `analytics`.
@DependencyClient
public struct AnalyticsClient: Sendable {
    /// Fire-and-forget. Providers must not block the caller.
    public var track: @Sendable (_ event: any TrackingEvent) -> Void
    // >>> option:identity
    /// A pseudonymous id only (never an email or name). `nil` clears it.
    public var setUserID: @Sendable (_ id: String?) -> Void
    /// Clears identity and super-properties (sign-out, environment switch).
    public var reset: @Sendable () -> Void
    // <<< option:identity
}

extension AnalyticsClient: DependencyKey {
    public static let liveValue: AnalyticsClient = {
        // >>> option:log-provider
        @Dependency(\.logger) var logger
        // <<< option:log-provider
        return .live(providers: [
            // >>> option:log-provider
            .log(logger),
            // <<< option:log-provider
            // >>> option:vendor
            // .vendor(),  // uncomment once the vendor SDK is wired in AnalyticsProvider+<Vendor>.swift
            // <<< option:vendor
        ])
    }()

    /// Unimplemented. Tests stub `track` and assert on the captured events.
    public static let testValue = AnalyticsClient()

    public static let previewValue = AnalyticsClient.live(providers: [])
}

public extension DependencyValues {
    var analytics: AnalyticsClient {
        get { self[AnalyticsClient.self] }
        set { self[AnalyticsClient.self] = newValue }
    }
}

extension AnalyticsClient {
    static func live(providers: [AnalyticsProvider]) -> Self {
        var client = AnalyticsClient()
        client.track = { event in
            if !TrackingEventName.isValid(event.name) || !event.parameters.keys.allSatisfy(TrackingEventName.isValid) {
                // A runtime warning in debug and a test failure in tests. The event is still sent.
                reportIssue("Analytics event '\(event.name)' breaks the naming rules")
            }
            for provider in providers {
                provider.track(event.name, event.parameters)
            }
        }
        // >>> option:identity
        client.setUserID = { id in
            for provider in providers { provider.setUserID(id) }
        }
        client.reset = {
            for provider in providers { provider.reset() }
        }
        // <<< option:identity
        return client
    }
}
