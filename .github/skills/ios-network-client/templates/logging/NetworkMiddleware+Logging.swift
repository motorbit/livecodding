import Foundation
import Logging

public extension NetworkMiddleware {
    /// Logs one line per wire attempt: method, host, path, redacted query keys, status and duration.
    /// It never logs headers (tokens, cookies), bodies or query values: they may contain PII.
    static func logging(logger: LoggingClient) -> NetworkMiddleware {
        NetworkMiddleware { next in
            { request in
                let start = ContinuousClock.now
                do {
                    let (data, response) = try await next(request)
                    var metadata = request.sanitizedMetadata
                    metadata["status"] = String(response.statusCode)
                    metadata["durationMs"] = (ContinuousClock.now - start).milliseconds
                    logger.info("HTTP response", metadata)
                    return (data, response)
                } catch {
                    var metadata = request.sanitizedMetadata
                    metadata["durationMs"] = (ContinuousClock.now - start).milliseconds
                    // Raw errors (e.g. URLError's failing URL in userInfo) may carry query values.
                    let networkError = NetworkError(error)
                    if networkError == .cancelled {
                        logger.debug("HTTP request cancelled", metadata)
                    } else {
                        logger.error(networkError, metadata)
                    }
                    throw error
                }
            }
        }
    }
}

extension URLRequest {
    /// Loggable description: `https://api.example.com/v1/items?page=<redacted>`.
    var sanitizedMetadata: [String: String] {
        var metadata = ["method": httpMethod ?? "GET"]
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return metadata
        }
        components.user = nil
        components.password = nil
        components.fragment = nil
        components.queryItems = components.queryItems?.map { URLQueryItem(name: $0.name, value: "<redacted>") }
        metadata["url"] = components.string ?? "<invalid>"
        return metadata
    }
}

private extension Duration {
    var milliseconds: String {
        let (seconds, attoseconds) = components
        return String(seconds * 1_000 + attoseconds / 1_000_000_000_000_000)
    }
}
