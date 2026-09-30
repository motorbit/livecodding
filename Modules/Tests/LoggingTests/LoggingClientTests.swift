import Dependencies
import Testing
@testable import Logging

struct LoggingClientTests {
    private struct Entry: Equatable, Sendable {
        let level: LogLevel
        let message: String
        let metadata: [String: String]
    }

    @Test("""
        Given a logging client,
        When a convenience level method is called,
        Then it forwards the level, message and metadata
        """)
    func warningForwardsEntry() {
        let entries = LockIsolated<[Entry]>([])
        let sut = LoggingClient(
            log: { level, message, metadata in
                entries.withValue { $0.append(Entry(level: level, message: message, metadata: metadata)) }
            },
            logError: { _, _ in }
        )

        sut.warning("Request failed", ["operation": "load"])

        #expect(entries.value == [Entry(level: .warning, message: "Request failed", metadata: ["operation": "load"])])
    }
}
