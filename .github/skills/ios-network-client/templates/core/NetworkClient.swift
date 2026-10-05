import Dependencies
import DependenciesMacros
import Foundation

/// One HTTP exchange: request in, body + HTTP response out. Middlewares wrap this signature.
public typealias HTTPSend = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

/// The app's single HTTP entry point. Feature-facing API clients (e.g. `ProfileClient`) are built
/// on top of it. Features don't call it directly.
///
/// The minimal version returns raw data for any status code; callers decide what's a success.
/// The `json` option adds status checks, typed `NetworkError` and `@concurrent` (off-main) exchanges.
@DependencyClient
public struct NetworkClient: Sendable {
    public var send: @Sendable (_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension NetworkClient: DependencyKey {
    /// Composed in `LiveNetworkClient.swift`.
    public static let liveValue: NetworkClient = .liveComposed()

    /// Unimplemented: each test stubs `send` (or uses `NetworkClient(send:)` with a closure).
    public static let testValue = NetworkClient()
}

public extension DependencyValues {
    var networkClient: NetworkClient {
        get { self[NetworkClient.self] }
        set { self[NetworkClient.self] = newValue }
    }
}
