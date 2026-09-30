import Dependencies
import Foundation
import Testing
@testable import __Name__Client

/// Tests the LIVE implementation against a sandboxed storage. Consumers of the client (VMs) stub
/// the endpoints with `withDependencies` instead; they never use this.
struct Live__Name__ClientTests {
    private func makeSandboxedClient() -> (__Name__Client, URL) {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).txt")
        return (__Name__Client.live(storage: Live__Name__Storage(fileURL: url)), url)
    }

    @Test("""
        Given a stored value,
        When load is called,
        Then it returns the value and caches it
        """)
    func loadReturnsAndCachesValue() async throws {
        let (sut, url) = makeSandboxedClient()
        defer { try? FileManager.default.removeItem(at: url) }
        try "stored".write(to: url, atomically: true, encoding: .utf8)

        let value = try await sut.load()

        #expect(value == "stored")
        #expect(sut.cachedValue() == "stored")
    }

    @Test("""
        Given no stored value,
        When load is called,
        Then it throws
        """)
    func loadWithoutValueThrows() async {
        let (sut, _) = makeSandboxedClient()

        await #expect(throws: (any Error).self) { try await sut.load() }
    }

    @Test("""
        Given a cached value,
        When clear is called,
        Then the cache is empty
        """)
    func clearEmptiesCache() async throws {
        let (sut, url) = makeSandboxedClient()
        try "stored".write(to: url, atomically: true, encoding: .utf8)
        _ = try await sut.load()

        await sut.clear()

        #expect(sut.cachedValue() == nil)
        #expect(FileManager.default.fileExists(atPath: url.path()) == false)
    }
}
