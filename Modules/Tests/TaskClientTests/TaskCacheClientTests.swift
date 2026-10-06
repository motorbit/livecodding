import Dependencies
import Foundation
import GRDB
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
    @Test("""
        Given a database file from before versions, with a queued delete,
        When it is opened by the current client,
        Then it is upgraded, the change is kept without a base version and versions can be recorded
        """)
    func upgradesDatabaseWithoutVersions() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "TaskCache.sqlite")
        let id = UUID()
        do {
            let old = try DatabaseQueue(path: url.path)
            try TaskCacheDatabase.migrator.migrate(old, upTo: "v2-create-pendingChange")
            try await old.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO pendingChange (scope, taskID, kind, isLocal, revision)
                        VALUES ('local', ?, 'delete', 0, 0)
                        """,
                    arguments: [id.uuidString]
                )
            }
            try old.close()
        }

        let sut = TaskCacheClient.live(database: TaskCacheDatabase(location: .file(url)))

        let pending = try await sut.pendingChanges("local")
        #expect(pending.map(\.kind) == [.delete])
        #expect(pending.first?.baseVersion == nil)
        try await sut.setVersions("local", [id: 2])
        var conflicts = sut.syncConflictCounts("local").makeAsyncIterator()
        #expect(await conflicts.next() == 0)
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

        try await sut.settle("local", change, .created(created, version: 1))

        #expect(try await sut.pendingChanges("local").isEmpty)
        #expect(try await sut.tasks("local") == [created])
        let resolved = try await sut.resolve("local", task.id)
        #expect(resolved == ResolvedTaskID(id: created.id, hasPendingChange: false))
    }

    @Test("""
        Given a recorded server version,
        When the task is updated offline, its version moves on and it is updated again,
        Then the change keeps the first version as its base
        """)
    func mergedChangeKeepsFirstBaseVersion() async throws {
        let sut = TaskCacheClient.inMemory()
        let other = TaskItem(id: UUID(), title: "Other", priority: .low)
        try await sut.setVersions("local", [task.id: 3, other.id: 7])
        try await sut.enqueue("local", .update(task))
        try await sut.setVersions("local", [task.id: 4])
        var edited = task
        edited.title = "Edited"
        try await sut.enqueue("local", .update(edited))
        try await sut.enqueue("local", .delete(other.id))
        try await sut.enqueue("local", .create(TaskItem(id: UUID(), title: "New", priority: .low)))

        let pending = try await sut.pendingChanges("local")

        #expect(pending.map(\.baseVersion) == [3, 7, nil])
        #expect(pending.first?.task?.title == "Edited")
    }

    @Test("""
        Given a queued update edited while being sent,
        When it settles as updated with the server's new version,
        Then the edit stays queued with that version as its base, which is also recorded
        """)
    func updateEditedInFlightTakesNewBase() async throws {
        let sut = TaskCacheClient.inMemory()
        try await sut.replaceAll("local", [task])
        try await sut.setVersions("local", [task.id: 1])
        try await sut.enqueue("local", .update(task))
        let change = try #require(try await sut.pendingChanges("local").first)
        var edited = task
        edited.title = "Edited"
        try await sut.enqueue("local", .update(edited))

        try await sut.settle("local", change, .updated(task, version: 2))

        let pending = try await sut.pendingChanges("local")
        #expect(pending.map(\.baseVersion) == [2])
        #expect(pending.first?.task?.title == "Edited")
        try await sut.enqueue("local", .delete(task.id))
        #expect(try await sut.pendingChanges("local").map(\.baseVersion) == [2])
    }

    @Test("""
        Given a queued update and an observer of the conflict count,
        When the update settles as a conflict and conflicts are then cleared,
        Then the change is removed and the count goes 0, 1, 0
        """)
    func conflictDropsChangeAndIsCountedUntilCleared() async throws {
        let sut = TaskCacheClient.inMemory()
        try await sut.replaceAll("local", [task])
        var conflicts = sut.syncConflictCounts("local").makeAsyncIterator()
        #expect(await conflicts.next() == 0)
        try await sut.enqueue("local", .update(task))
        let change = try #require(try await sut.pendingChanges("local").first)

        try await sut.settle("local", change, .conflict)

        #expect(try await sut.pendingChanges("local").isEmpty)
        #expect(try await sut.tasks("local") == [task])
        #expect(await conflicts.next() == 1)
        try await sut.clearSyncConflicts("local")
        #expect(await conflicts.next() == 0)
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
