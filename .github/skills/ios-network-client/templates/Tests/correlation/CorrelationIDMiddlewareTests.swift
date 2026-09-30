import Dependencies
import Foundation
import Testing
@testable import NetworkClient

struct CorrelationIDMiddlewareTests {
    private let url = URL(string: "https://api.example.com/items")!

    @Test("""
        Given a request without a correlation ID,
        When it is sent,
        Then the generated ID is added
        """)
    func addsHeader() async throws {
        let seen = LockIsolated<String?>(nil)
        let send = [NetworkMiddleware.correlationID { "id-1" }].compose { request in
            seen.setValue(request.value(forHTTPHeaderField: NetworkMiddleware.correlationIDHeader))
            return (Data(), .stub(request, status: 200))
        }

        _ = try await send(URLRequest(url: url))

        #expect(seen.value == "id-1")
    }

    @Test("""
        Given a request that already has a correlation ID,
        When it is sent,
        Then the existing ID is kept
        """)
    func keepsExistingHeader() async throws {
        let seen = LockIsolated<String?>(nil)
        var request = URLRequest(url: url)
        request.setValue("upstream", forHTTPHeaderField: NetworkMiddleware.correlationIDHeader)
        let send = [NetworkMiddleware.correlationID { "id-1" }].compose { request in
            seen.setValue(request.value(forHTTPHeaderField: NetworkMiddleware.correlationIDHeader))
            return (Data(), .stub(request, status: 200))
        }

        _ = try await send(request)

        #expect(seen.value == "upstream")
    }
}
