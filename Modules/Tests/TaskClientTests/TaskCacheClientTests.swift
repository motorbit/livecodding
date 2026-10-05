import Dependencies
import Foundation
import Testing
@testable import TaskClient

struct TaskCacheClientTests {
    @Test("""
        Given an in-memory cache,
        When a list is replaced, upserted and deleted from,
        Then order is kept, new tasks append and updates stay in place
        """)
    func replaceUpsertDelete() async throws {
        let sut = TaskCacheClient.inMemory()
        let samples = TaskItem.samples
        try await sut.replaceAll("local", samples)
        #expect(try await sut.tasks("local") == samples)

        var updated = samples[0]
        updated.title = "Renamed"
        updated.dueDate = Date(timeIntervalSince1970: 1_790_000_000)
        try await sut.upsert("local", updated)
        let added = TaskItem(id: UUID(), title: "Added", priority: .low)
        try await sut.upsert("local", added)
        try await sut.delete("local", samples[1].id)

        #expect(try await sut.tasks("local") == [updated, samples[2], samples[3], added])

        try await sut.replaceAll("local", [added])
        #expect(try await sut.tasks("local") == [added])
    }

    @Test("""
        Given tasks cached under one scope,
        When another scope is read or replaced,
        Then the scopes don't affect each other
        """)
    func scopesAreIsolated() async throws {
        let sut = TaskCacheClient.inMemory()
        try await sut.replaceAll("local", TaskItem.samples)

        #expect(try await sut.tasks("dev").isEmpty)
        try await sut.replaceAll("dev", [])
        #expect(try await sut.tasks("local") == TaskItem.samples)
    }

    @Test("""
        Given a scope with no full list stored,
        When a task is upserted,
        Then the scope still reads as empty until replaceAll runs
        """)
    func upsertWithoutFullListIsIgnored() async throws {
        let sut = TaskCacheClient.inMemory()
        let added = TaskItem(id: UUID(), title: "Added", priority: .low)

        try await sut.upsert("dev", added)
        #expect(try await sut.tasks("dev").isEmpty)

        try await sut.replaceAll("dev", [])
        try await sut.upsert("dev", added)
        #expect(try await sut.tasks("dev") == [added])
    }

    @Test("""
        Given tasks cached under two scopes,
        When the cache is cleared,
        Then both scopes are empty
        """)
    func clearRemovesEveryScope() async throws {
        let sut = TaskCacheClient.inMemory()
        try await sut.replaceAll("local", TaskItem.samples)
        try await sut.replaceAll("dev", TaskItem.samples)

        try await sut.clear()

        #expect(try await sut.tasks("local").isEmpty)
        #expect(try await sut.tasks("dev").isEmpty)
    }

    @Test("""
        Given tasks cached in a database file,
        When the file is opened again by a new client,
        Then the tasks are still there
        """)
    func persistsAcrossOpens() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "TaskCache.sqlite")

        try await TaskCacheClient.live(database: TaskCacheDatabase(location: .file(url)))
            .replaceAll("local", TaskItem.samples)
        let reopened = TaskCacheClient.live(database: TaskCacheDatabase(location: .file(url)))

        #expect(try await reopened.tasks("local") == TaskItem.samples)
    }
}
