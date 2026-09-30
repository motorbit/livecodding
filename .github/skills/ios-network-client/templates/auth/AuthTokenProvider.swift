import Dependencies
import DependenciesMacros

/// Supplies bearer tokens to the network `auth` middleware. It's only the interface: the module
/// that owns sign-in (out of scope for this kit) provides the live implementation with
///
///     extension AuthTokenProvider: DependencyKey {
///         public static let liveValue = AuthTokenProvider(token: { … }, refresh: { … })
///     }
///
/// If no module provides `liveValue`, swift-dependencies reports a missing live value at runtime.
@DependencyClient
public struct AuthTokenProvider: Sendable {
    /// A currently valid access token (possibly cached).
    public var token: @Sendable () async throws -> String
    /// Forces a refresh and returns the new token. Called at most once per 401 burst (single-flight).
    public var refresh: @Sendable () async throws -> String
}

extension AuthTokenProvider: TestDependencyKey {
    public static let testValue = AuthTokenProvider()
}

public extension DependencyValues {
    var authTokenProvider: AuthTokenProvider {
        get { self[AuthTokenProvider.self] }
        set { self[AuthTokenProvider.self] = newValue }
    }
}
