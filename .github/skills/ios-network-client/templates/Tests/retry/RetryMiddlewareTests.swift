import Dependencies
import Foundation
import Testing
@testable import NetworkClient

struct RetryMiddlewareTests {
    private let url = URL(string: "https://api.example.com/items")!
    private let policy = RetryPolicy(maxAttempts: 3, jitter: { 1 })

    @Test("""
        Given a GET that fails with 503 twice and then succeeds,
        When it is sent,
        Then it is attempted three times and returns 200
        """)
    func retriesTransientStatus() async throws {
        let attempts = LockIsolated(0)
        let send = [NetworkMiddleware.retry(policy: policy, clock: ImmediateClock())].compose { request in
            let attempt = attempts.withValue { $0 += 1; return $0 }
            return (Data(), .stub(request, status: attempt < 3 ? 503 : 200))
        }

        let (_, response) = try await send(URLRequest(url: url))

        #expect(attempts.value == 3)
        #expect(response.statusCode == 200)
    }

    @Test("""
        Given a POST that fails with 503,
        When it is sent,
        Then it is not retried
        """)
    func doesNotRetryNonIdempotent() async throws {
        let attempts = LockIsolated(0)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let send = [NetworkMiddleware.retry(policy: policy, clock: ImmediateClock())].compose { request in
            attempts.withValue { $0 += 1 }
            return (Data(), .stub(request, status: 503))
        }

        let (_, response) = try await send(request)

        #expect(attempts.value == 1)
        #expect(response.statusCode == 503)
    }

    @Test("""
        Given a GET that times out every time,
        When it is sent,
        Then it gives up after maxAttempts and rethrows
        """)
    func givesUpAfterMaxAttempts() async {
        let attempts = LockIsolated(0)
        let send = [NetworkMiddleware.retry(policy: policy, clock: ImmediateClock())].compose { _ in
            attempts.withValue { $0 += 1 }
            throw URLError(.timedOut)
        }

        await #expect(throws: URLError.self) { try await send(URLRequest(url: self.url)) }
        #expect(attempts.value == 3)
    }

    @Test("""
        Given a policy with base 300ms, cap 1s and no jitter,
        When delays are computed,
        Then they grow exponentially up to the cap
        """)
    func backoffDelays() {
        let policy = RetryPolicy(baseDelay: .milliseconds(300), maxDelay: .seconds(1), jitter: { 1 })

        #expect(policy.delay(afterAttempt: 1) == .milliseconds(300))
        #expect(policy.delay(afterAttempt: 2) == .milliseconds(600))
        #expect(policy.delay(afterAttempt: 3) == .seconds(1))
    }
}
