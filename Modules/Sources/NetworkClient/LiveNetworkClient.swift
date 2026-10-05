import Dependencies
import Foundation
import Logging

extension NetworkClient {
    /// Live composition. Order (outer → inner): logging → transport, so each wire attempt is logged.
    static func liveComposed() -> NetworkClient {
        @Dependency(\.logger) var logger
        let middlewares: [NetworkMiddleware] = [
            .logging(logger: logger),
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
