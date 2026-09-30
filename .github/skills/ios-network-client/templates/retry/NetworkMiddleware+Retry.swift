import Foundation

/// When and how long to wait between attempts.
public struct RetryPolicy: Sendable {
    /// Total attempts, including the first one.
    public var maxAttempts: Int
    public var baseDelay: Duration
    public var maxDelay: Duration
    public var retryableStatusCodes: Set<Int>
    public var retryableURLErrors: Set<URLError.Code>
    /// Only these methods are retried: replaying a POST can duplicate side effects.
    public var retryableMethods: Set<String>
    /// Multiplier applied to each delay, in 0...1. Randomized in live; fixed in tests.
    public var jitter: @Sendable () -> Double

    public init(
        maxAttempts: Int = 3,
        baseDelay: Duration = .milliseconds(300),
        maxDelay: Duration = .seconds(5),
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
        retryableURLErrors: Set<URLError.Code> = [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet],
        retryableMethods: Set<String> = ["GET", "HEAD", "OPTIONS", "PUT", "DELETE"],
        jitter: @escaping @Sendable () -> Double = { Double.random(in: 0.5...1.0) }
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.retryableStatusCodes = retryableStatusCodes
        self.retryableURLErrors = retryableURLErrors
        self.retryableMethods = retryableMethods
        self.jitter = jitter
    }

    public static let `default` = RetryPolicy()

    /// Exponential: base × 2^(attempt-1), capped at `maxDelay`, then multiplied by jitter.
    func delay(afterAttempt attempt: Int) -> Duration {
        let exponential = baseDelay * (1 << min(attempt - 1, 16))
        return min(exponential, maxDelay) * jitter()
    }
}

public extension NetworkMiddleware {
    /// Retries transient failures of idempotent requests with exponential backoff and jitter.
    /// Honours cancellation: `clock.sleep` throws `CancellationError` and nothing is retried.
    static func retry(policy: RetryPolicy, clock: any Clock<Duration>) -> NetworkMiddleware {
        NetworkMiddleware { next in
            { request in
                let method = request.httpMethod ?? "GET"
                guard policy.retryableMethods.contains(method), policy.maxAttempts > 1 else {
                    return try await next(request)
                }
                var attempt = 1
                while true {
                    do {
                        let (data, response) = try await next(request)
                        guard policy.retryableStatusCodes.contains(response.statusCode),
                              attempt < policy.maxAttempts else {
                            return (data, response)
                        }
                    } catch let error as URLError where policy.retryableURLErrors.contains(error.code) {
                        guard attempt < policy.maxAttempts else { throw error }
                    }
                    try await clock.sleep(for: policy.delay(afterAttempt: attempt))
                    attempt += 1
                }
            }
        }
    }
}
