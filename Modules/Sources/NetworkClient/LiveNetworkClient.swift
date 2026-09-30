import Dependencies
import Foundation

extension NetworkClient {
    /// Live composition. Selected middleware wraps the URLSession transport.
    static func liveComposed() -> NetworkClient {
        let middlewares: [NetworkMiddleware] = [
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
