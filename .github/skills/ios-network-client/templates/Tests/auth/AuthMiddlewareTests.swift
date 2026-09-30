import Dependencies
import Foundation
import Testing
@testable import NetworkClient

struct AuthMiddlewareTests {
    private let request = URLRequest(url: URL(string: "https://api.example.com/me")!)

    @Test("""
        Given a valid token,
        When a request is sent,
        Then it carries the bearer header and refresh is not called
        """)
    func addsBearerToken() async throws {
        let seen = LockIsolated<[String?]>([])
        let provider = AuthTokenProvider(token: { "t1" }, refresh: { Issue.record("unexpected refresh"); return "" })
        let send = [NetworkMiddleware.auth(tokenProvider: provider)].compose { request in
            seen.withValue { $0.append(request.value(forHTTPHeaderField: "Authorization")) }
            return (Data(), .stub(request, status: 200))
        }

        _ = try await send(request)

        #expect(seen.value == ["Bearer t1"])
    }

    @Test("""
        Given a 401 for the first token,
        When a request is sent,
        Then the token is refreshed once and the request is retried with the new token
        """)
    func refreshesOn401() async throws {
        let seen = LockIsolated<[String?]>([])
        let provider = AuthTokenProvider(token: { "old" }, refresh: { "new" })
        let send = [NetworkMiddleware.auth(tokenProvider: provider)].compose { request in
            let header = request.value(forHTTPHeaderField: "Authorization")
            seen.withValue { $0.append(header) }
            return (Data(), .stub(request, status: header == "Bearer old" ? 401 : 200))
        }

        let (_, response) = try await send(request)

        #expect(response.statusCode == 200)
        #expect(seen.value == ["Bearer old", "Bearer new"])
    }

    @Test("""
        Given many concurrent 401s for the same token,
        When they all refresh,
        Then refresh runs exactly once
        """)
    func singleFlightRefresh() async throws {
        let refreshCount = LockIsolated(0)
        let refresher = SingleFlightTokenRefresher(refresh: {
            refreshCount.withValue { $0 += 1 }
            await Task.yield()
            return "new"
        })

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<10 {
                group.addTask { try await refresher.token(replacing: "old") }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(tokens == Array(repeating: "new", count: 10))
        #expect(refreshCount.value == 1)
    }
}
