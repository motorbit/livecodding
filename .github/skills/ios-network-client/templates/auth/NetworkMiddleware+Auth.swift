import Foundation

public extension NetworkMiddleware {
    /// Adds `Authorization: Bearer <token>`. On a 401 it refreshes the token once (single-flight
    /// across concurrent requests) and retries the request once. A second 401 is returned as is.
    ///
    /// - Parameter requiresAuth: return `false` for anonymous requests (e.g. the refresh call
    ///   itself, if it goes through this client).
    static func auth(
        tokenProvider: AuthTokenProvider,
        requiresAuth: @escaping @Sendable (URLRequest) -> Bool = { _ in true }
    ) -> NetworkMiddleware {
        let refresher = SingleFlightTokenRefresher(refresh: tokenProvider.refresh)
        return NetworkMiddleware { next in
            { request in
                guard requiresAuth(request) else { return try await next(request) }

                let token = try await tokenProvider.token()
                let (data, response) = try await next(request.authorized(with: token))
                guard response.statusCode == 401 else { return (data, response) }

                let freshToken = try await refresher.token(replacing: token)
                return try await next(request.authorized(with: freshToken))
            }
        }
    }
}

/// Makes N concurrent 401s cause exactly one `refresh()`.
/// - While a refresh is running, callers await the same `Task`.
/// - A caller whose rejected token was already replaced gets the newer token without a refresh.
actor SingleFlightTokenRefresher {
    private let refresh: @Sendable () async throws -> String
    private var inFlight: Task<String, any Error>?
    private var latestToken: String?

    init(refresh: @escaping @Sendable () async throws -> String) {
        self.refresh = refresh
    }

    func token(replacing rejected: String) async throws -> String {
        if let latestToken, latestToken != rejected {
            return latestToken
        }
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task { [refresh] in try await refresh() }
        inFlight = task
        defer { inFlight = nil }
        let token = try await task.value
        latestToken = token
        return token
    }
}

private extension URLRequest {
    func authorized(with token: String) -> URLRequest {
        var request = self
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}
