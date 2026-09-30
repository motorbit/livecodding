import Foundation

public extension NetworkMiddleware {
    static let correlationIDHeader = "X-Correlation-ID"

    /// Adds a correlation ID to every request that doesn't already have one, so client logs and
    /// server traces can be joined. Retries (inner middlewares) reuse the same ID.
    static func correlationID(
        header: String = correlationIDHeader,
        generate: @escaping @Sendable () -> String
    ) -> NetworkMiddleware {
        NetworkMiddleware { next in
            { request in
                guard request.value(forHTTPHeaderField: header) == nil else {
                    return try await next(request)
                }
                var request = request
                request.setValue(generate(), forHTTPHeaderField: header)
                return try await next(request)
            }
        }
    }
}
