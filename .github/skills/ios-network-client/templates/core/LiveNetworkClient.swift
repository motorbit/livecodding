import Dependencies
import Foundation
// >>> option:logging
import Logging
// <<< option:logging

extension NetworkClient {
    /// Live composition. Order (outer → inner) is fixed: correlation → retry → auth → logging →
    /// transport. With that order:
    /// - every retry reuses the same correlation ID,
    /// - a 401 refresh happens inside a single attempt,
    /// - each wire attempt is logged.
    /// Delete the entries (and files) of options that weren't selected.
    static func liveComposed() -> NetworkClient {
        // >>> option:logging
        @Dependency(\.logger) var logger
        // <<< option:logging
        // >>> option:retry
        @Dependency(\.continuousClock) var clock
        // <<< option:retry
        // >>> option:auth
        @Dependency(\.authTokenProvider) var tokenProvider
        // <<< option:auth
        // >>> option:correlation
        @Dependency(\.uuid) var uuid
        let generateID = uuid  // copy: Sendable closures can't capture a wrapped local var
        // <<< option:correlation

        let middlewares: [NetworkMiddleware] = [
            // >>> option:correlation
            .correlationID { generateID().uuidString },
            // <<< option:correlation
            // >>> option:retry
            .retry(policy: .default, clock: clock),
            // <<< option:retry
            // >>> option:auth
            .auth(tokenProvider: tokenProvider),
            // <<< option:auth
            // >>> option:logging
            .logging(logger: logger),
            // <<< option:logging
        ]
        return NetworkClient(send: middlewares.compose(around: urlSessionTransport(.shared)))
    }

    /// The only place that touches `URLSession`. `data(for:)` suspends and doesn't block the caller.
    static func urlSessionTransport(_ session: URLSession) -> HTTPSend {
        { request in
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return (data, httpResponse)
        }
    }
}
