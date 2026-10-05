import Dependencies
import Foundation
import Logging
import Testing
@testable import NetworkClient

struct LoggingMiddlewareTests {
    private struct Entry: Equatable, Sendable {
        let message: String
        let metadata: [String: String]
    }

    @Test("""
        Given a request with credentials, a token, a body and query values,
        When it succeeds,
        Then one line is logged with method, sanitized URL and status and nothing sensitive
        """)
    func logsSanitizedMetadata() async throws {
        let entries = LockIsolated<[Entry]>([])
        var logger = LoggingClient()
        logger.log = { _, message, metadata in
            entries.withValue { $0.append(Entry(message: message, metadata: metadata)) }
        }
        var request = URLRequest(url: URL(string: "https://user:pw@api.example.com/v1/search?q=alice@example.com#frag")!)
        request.httpMethod = "POST"
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("password".utf8)
        let send = [NetworkMiddleware.logging(logger: logger)].compose { request in
            (Data("response-body".utf8), .stub(request, status: 200))
        }

        _ = try await send(request)

        #expect(entries.value.count == 1)
        let metadata = try #require(entries.value.first).metadata
        #expect(metadata["method"] == "POST")
        #expect(metadata["url"] == "https://api.example.com/v1/search?q=%3Credacted%3E")
        #expect(metadata["status"] == "200")
        #expect(metadata["durationMs"] != nil)
        let all = metadata.values.joined()
        for secret in ["secret", "alice", "password", "pw", "user", "frag", "response-body"] {
            #expect(!all.contains(secret))
        }
    }

    @Test("""
        Given the transport fails with a URL error carrying the full URL,
        When the request is sent,
        Then the mapped error is logged with sanitized metadata and the original error is rethrown
        """)
    func logsAndRethrowsFailure() async {
        let logged = LockIsolated<(error: String, metadata: [String: String])?>(nil)
        var logger = LoggingClient()
        logger.logError = { error, metadata in
            logged.setValue((String(describing: error), metadata))
        }
        let url = "https://api.example.com/v1/items?email=alice@example.com"
        let request = URLRequest(url: URL(string: url)!)
        let failure = URLError(.timedOut, userInfo: [NSURLErrorFailingURLStringErrorKey: url])
        let send = [NetworkMiddleware.logging(logger: logger)].compose { _ in throw failure }

        await #expect(throws: failure) {
            try await send(request)
        }
        #expect(logged.value?.error == String(describing: NetworkError.transport(.timedOut)))
        #expect(logged.value?.error.contains("alice") == false)
        #expect(logged.value?.metadata["method"] == "GET")
        #expect(logged.value?.metadata["url"] == "https://api.example.com/v1/items?email=%3Credacted%3E")
        #expect(logged.value?.metadata["status"] == nil)
    }

    @Test("""
        Given the request is cancelled,
        When the transport throws a cancellation,
        Then it is logged at debug level, not as an error
        """)
    func logsCancellationAtDebug() async {
        let levels = LockIsolated<[LogLevel]>([])
        var logger = LoggingClient()
        logger.log = { level, _, _ in levels.withValue { $0.append(level) } }
        let request = URLRequest(url: URL(string: "https://api.example.com/v1/items")!)
        let send = [NetworkMiddleware.logging(logger: logger)].compose { _ in throw CancellationError() }

        await #expect(throws: CancellationError.self) {
            try await send(request)
        }
        #expect(levels.value == [.debug])
    }
}
