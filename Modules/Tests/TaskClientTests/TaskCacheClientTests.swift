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

struct TaskCachePendingChangeTests {
    private let task = TaskItem(id: UUID(), title: "Offline", priority: .low)

    @Test("""
        Given a queued create,
        When the task is updated and then deleted,
        Then one change remains per task, ending as a local delete
        """)
    func changesMergePerTask() async throws {
        let sut = TaskCacheClient.inMemory()
        try await sut.enqueue("local", .create(task))
        var edited = task
        edited.title = "Edited"
        try await sut.enqueue("local", .update(edited))

        var pending = try await sut.pendingChanges("local")
        #expect(pending.count == 1)
        #expect(pending.first?.kind == .create)
        #expect(pending.first?.task?.title == "Edited")
        #expect(pending.first?.revision == 1)

        try await sut.enqueue("local", .delete(task.id))
        try await sut.enqueue("local", .update(edited))
        pending = try await sut.pendingChanges("local")
        #expect(pending.map(\.kind) == [.delete])
        #expect(pending.first?.isLocal == true)
        #expect(pending.first?.task == nil)
    }

    @Test("""
        Given a queued create sent without edits in between,
        When the server's task is recorded,
        Then the change is removed and the local id resolves to the server id
        """)
    func settledCreateRecordsAlias() async throws {
        let sut = TaskCacheClient.inMemory()
        try await sut.replaceAll("local", [])
        try await sut.enqueue("local", .create(task))
        let change = try #require(try await sut.pendingChanges("local").first)
        let created = TaskItem(id: UUID(), title: "Offline", priority: .low)

        try await sut.settle("local", change, .created(created))

        #expect(try await sut.pendingChanges("local").isEmpty)
        #expect(try await sut.tasks("local") == [created])
        let resolved = try await sut.resolve("local", task.id)
        #expect(resolved == ResolvedTaskID(id: created.id, hasPendingChange: false))
    }

    @Test("""
        Given queued changes in two scopes,
        When the cache is cleared,
        Then no changes remain in any scope
        """)
    func clearRemovesPendingChanges() async throws {
        let sut = TaskCacheClient.inMemory()
        try await sut.enqueue("local", .create(task))
        try await sut.enqueue("dev", .delete(UUID()))

        try await sut.clear()

        #expect(try await sut.pendingChanges("local").isEmpty)
        #expect(try await sut.pendingChanges("dev").isEmpty)
    }
}
