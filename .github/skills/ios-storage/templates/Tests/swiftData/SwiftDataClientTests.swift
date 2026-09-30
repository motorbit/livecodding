import Foundation
import Testing
@testable import __Module__

/// Runs the real SwiftData stack over an in-memory store; each test gets its own container.
struct SwiftDataClientTests {
    @Test("""
        Given an empty in-memory store,
        When two items are saved,
        Then they're fetched sorted by id
        """)
    func saveAndFetch() async throws {
        let sut = SwiftDataClient.inMemory()

        try await sut.save__Model__(.fixture(id: "b"))
        try await sut.save__Model__(.fixture(id: "a"))

        #expect(try await sut.fetch__Models__().map(\.id) == ["a", "b"])
    }

    @Test("""
        Given a stored item,
        When an item with the same id is saved,
        Then it's updated, not duplicated
        """)
    func saveUpserts() async throws {
        let sut = SwiftDataClient.inMemory()
        try await sut.save__Model__(.fixture(id: "a"))
        let updated = __Model__.fixture(id: "a", variant: 2)

        try await sut.save__Model__(updated)

        #expect(try await sut.fetch__Models__() == [updated])
    }

    @Test("""
        Given two stored items,
        When one is deleted and a missing id is deleted,
        Then only the other remains and no error is thrown
        """)
    func deleteByID() async throws {
        let sut = SwiftDataClient.inMemory()
        try await sut.save__Model__(.fixture(id: "a"))
        try await sut.save__Model__(.fixture(id: "b"))

        try await sut.delete__Model__("a")
        try await sut.delete__Model__("missing")

        #expect(try await sut.fetch__Models__().map(\.id) == ["b"])
    }

    @Test("""
        Given stored items,
        When deleteAll is called,
        Then the store is empty
        """)
    func deleteAllEmptiesStore() async throws {
        let sut = SwiftDataClient.inMemory()
        try await sut.save__Model__(.fixture(id: "a"))

        try await sut.deleteAll()

        #expect(try await sut.fetch__Models__().isEmpty)
    }

    @Test("""
        Given two in-memory clients,
        When one saves an item,
        Then the other stays empty
        """)
    func inMemoryStoresAreIsolated() async throws {
        let first = SwiftDataClient.inMemory()
        let second = SwiftDataClient.inMemory()

        try await first.save__Model__(.fixture(id: "a"))

        #expect(try await second.fetch__Models__().isEmpty)
    }
}

private extension __Model__ {
    /// Builds a value whose fields differ per `variant`. Adjust to the model's fields.
    static func fixture(id: String, variant: Int = 1) -> Self {
        // >>> fields
        __Model__(id: id, title: "title \(variant)")
        // <<< fields
    }
}
