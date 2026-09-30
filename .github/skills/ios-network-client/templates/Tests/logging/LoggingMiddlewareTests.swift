import Dependencies
import Foundation
import Logging
import Testing
@testable import NetworkClient

struct LoggingMiddlewareTests {
    @Test("""
        Given a request with a token and query values,
        When it is logged,
        Then no header, body or query value appears in the log
        """)
    func logsSanitizedMetadata() async throws {
        let logged = LockIsolated<[String: String]>([:])
        var logger = LoggingClient()
        logger.log = { _, _, metadata in logged.setValue(metadata) }
        var request = URLRequest(url: URL(string: "https://user:pw@api.example.com/v1/search?q=alice@example.com#frag")!)
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("password".utf8)
        let send = [NetworkMiddleware.logging(logger: logger)].compose { request in
            (Data(), .stub(request, status: 200))
        }

        _ = try await send(request)

        #expect(logged.value["url"] == "https://api.example.com/v1/search?q=%3Credacted%3E")
        #expect(logged.value["status"] == "200")
        let all = logged.value.values.joined()
        #expect(!all.contains("secret") && !all.contains("alice") && !all.contains("password") && !all.contains("pw"))
    }
}
