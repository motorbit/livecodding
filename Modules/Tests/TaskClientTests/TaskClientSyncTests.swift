import AppEnvironment
import Dependencies
import Foundation
import Logging
import Testing
@testable import TaskClient

/// The instant mock server behind a switch: while offline every call throws `.transport`.
private final class Server: Sendable {
    let isOnline = LockIsolated(true)
    let calls = LockIsolated<[String]>([])
    let mock = TaskNetworkClient.mock(policy: .instant)

    var client: TaskNetworkClient {
        TaskNetworkClient(
            fetchTasks: {
                try self.record("fetch")
                return try await self.mock.fetchTasks()
            },
            createTask: { body, key in
                try self.record("create \(body.title)")
                return try await self.mock.createTask(body, key)
            },
            updateTask: { body in
                try self.record("update \(body.title)")
                return try await self.mock.updateTask(body)
            },
            deleteTask: { id in
                try self.record("delete")
                try await self.mock.deleteTask(id)
            }
        )
    }

    private func record(_ call: String) throws {
        guard isOnline.value else { throw TaskNetworkError.transport }
        calls.withValue { $0.append(call) }
    }
}

private func makeDependencies(_ dependencies: inout DependencyValues, server: Server) {
    dependencies.environmentClient.current = { EnvironmentConfig(environment: .local, apiBackend: .mock) }
    dependencies.taskCacheClient = .inMemory()
    dependencies.taskNetworkClient = server.client
    dependencies.uuid = UUIDGenerator { UUID() }
}

struct TaskClientSyncTests {
    @Test("""
        Given a fetched list and no connection,
        When a task is created and the connection returns,
        Then it is shown as pending, then the next fetch sends it and returns the server's task
        """)
    func offlineCreateSyncsOnNextFetch() async throws {
        let server = Server()
        try await withDependencies { makeDependencies(&$0, server: server) } operation: {
            let sut = TaskClient.repository
            _ = try await sut.fetchTasks()
            server.isOnline.setValue(false)

            let local = try await sut.createTask(TaskDraft(title: " Offline ", priority: .high))
            #expect(local.isPendingSync)
            #expect(local.title == "Offline")
            let cached = try await sut.cachedTasks()
            #expect(cached.count == 5)
            #expect(cached.last == local)

            server.isOnline.setValue(true)
            let synced = try await sut.fetchTasks()

            #expect(synced.count == 5)
            #expect(synced.last?.title == "Offline")
            #expect(synced.last?.isPendingSync == false)
            #expect(synced.last?.id != local.id)
            #expect(server.calls.value == ["fetch", "create Offline", "fetch"])
            let afterSync = try await sut.cachedTasks()
            #expect(afterSync == synced)
        }
    }

    @Test("""
        Given a queued change and still no connection,
        When tasks are fetched,
        Then unavailable is thrown and the change stays queued
        """)
    func failedSyncKeepsChangeQueued() async throws {
        let server = Server()
        server.isOnline.setValue(false)
        try await withDependencies { makeDependencies(&$0, server: server) } operation: {
            let sut = TaskClient.repository
            var task = TaskItem.samples[0]
            task.isComplete = true
            let queued = try await sut.updateTask(task)
            #expect(queued.isPendingSync)

            await #expect(throws: TaskClientError.unavailable) { try await sut.fetchTasks() }
            @Dependency(\.taskCacheClient) var cache
            let pending = try await cache.pendingChanges("local")
            #expect(pending.map(\.kind) == [.update])
            #expect(server.calls.value.isEmpty)
        }
    }

    @Test("""
        Given a task created offline,
        When it is edited and completed offline,
        Then one create is sent with the latest values, followed by the completion
        """)
    func editsMergeIntoQueuedCreate() async throws {
        let server = Server()
        try await withDependencies { makeDependencies(&$0, server: server) } operation: {
            let sut = TaskClient.repository
            _ = try await sut.fetchTasks()
            server.isOnline.setValue(false)
            var local = try await sut.createTask(TaskDraft(title: "Draft"))
            local.title = "Final"
            local.isComplete = true
            let updated = try await sut.updateTask(local)
            #expect(updated.isPendingSync)

            server.isOnline.setValue(true)
            let synced = try await sut.fetchTasks()

            #expect(server.calls.value == ["fetch", "create Final", "update Final", "fetch"])
            #expect(synced.last?.title == "Final")
            #expect(synced.last?.isComplete == true)
        }
    }

    @Test("""
        Given a task created offline,
        When it is deleted before the connection returns,
        Then nothing is sent for it
        """)
    func deletedOfflineCreateIsNeverSent() async throws {
        let server = Server()
        try await withDependencies { makeDependencies(&$0, server: server) } operation: {
            let sut = TaskClient.repository
            _ = try await sut.fetchTasks()
            server.isOnline.setValue(false)
            let local = try await sut.createTask(TaskDraft(title: "Temp"))
            try await sut.deleteTask(local.id)
            let cached = try await sut.cachedTasks()
            #expect(cached == TaskItem.samples)

            server.isOnline.setValue(true)
            let synced = try await sut.fetchTasks()

            #expect(server.calls.value == ["fetch", "fetch"])
            #expect(synced == TaskItem.samples)
        }
    }

    @Test("""
        Given a task created offline and synced since,
        When it is updated with the local id the screen still holds,
        Then the server's task is updated and the caller's id is kept
        """)
    func localIDMapsToServerIDAfterSync() async throws {
        let server = Server()
        try await withDependencies { makeDependencies(&$0, server: server) } operation: {
            let sut = TaskClient.repository
            _ = try await sut.fetchTasks()
            server.isOnline.setValue(false)
            var local = try await sut.createTask(TaskDraft(title: "Offline"))
            server.isOnline.setValue(true)
            let serverID = try #require(try await sut.fetchTasks().last?.id)

            local.isComplete = true
            let saved = try await sut.updateTask(local)

            #expect(saved.id == local.id)
            #expect(saved.isPendingSync == false)
            let onServer = try await server.mock.fetchTasks().last
            #expect(onServer?.id == serverID)
            #expect(onServer?.done == true)
        }
    }

    @Test("""
        Given a queued update of a task deleted on the server meanwhile,
        When the queue is sent,
        Then the change is dropped and logged and the fetch still returns the server list
        """)
    func refusedChangeIsDroppedAndLogged() async throws {
        let server = Server()
        let logged = LockIsolated<[String]>([])
        try await withDependencies {
            makeDependencies(&$0, server: server)
            $0.logger.log = { _, _, metadata in
                logged.withValue { $0.append(metadata["operation"] ?? "") }
            }
        } operation: {
            let sut = TaskClient.repository
            server.isOnline.setValue(false)
            var task = TaskItem.samples[0]
            task.title = "Edited"
            _ = try await sut.updateTask(task)
            try await server.mock.deleteTask(task.id)
            server.isOnline.setValue(true)

            let synced = try await sut.fetchTasks()

            #expect(synced == Array(TaskItem.samples.dropFirst()))
            #expect(server.calls.value == ["update Edited", "fetch"])
        }
        #expect(logged.value == ["taskSync.rejected"])
    }

    @Test("""
        Given a create being sent,
        When the task is edited before the server answers,
        Then the edit stays queued and is sent to the server's task in the same sync
        """)
    func editDuringSendStaysQueued() async throws {
        let server = Server()
        let cache = TaskCacheClient.inMemory()
        let localID = LockIsolated<UUID?>(nil)
        try await withDependencies {
            makeDependencies(&$0, server: server)
            $0.taskCacheClient = cache
            let network = server.client
            $0.taskNetworkClient.createTask = { body, key in
                let created = try await network.createTask(body, key)
                if let id = localID.value {
                    try await cache.enqueue("local", .update(TaskItem(id: id, title: "Edited", priority: .low)))
                }
                return created
            }
        } operation: {
            let sut = TaskClient.repository
            server.isOnline.setValue(false)
            let local = try await sut.createTask(TaskDraft(title: "First"))
            localID.setValue(local.id)
            server.isOnline.setValue(true)

            let synced = try await sut.fetchTasks()

            #expect(server.calls.value == ["create First", "update Edited", "fetch"])
            #expect(synced.last?.title == "Edited")
            let pending = try await cache.pendingChanges("local")
            #expect(pending.isEmpty)
        }
    }

    @Test("""
        Given an observer of the pending count,
        When a change is queued offline and then synced,
        Then it reports 0, 1 and 0
        """)
    func pendingCountFollowsTheQueue() async throws {
        let server = Server()
        try await withDependencies { makeDependencies(&$0, server: server) } operation: {
            let sut = TaskClient.repository
            var counts = sut.pendingSyncCounts().makeAsyncIterator()
            #expect(await counts.next() == 0)

            server.isOnline.setValue(false)
            _ = try await sut.createTask(TaskDraft(title: "Offline"))
            #expect(await counts.next() == 1)

            server.isOnline.setValue(true)
            _ = try await sut.fetchTasks()
            #expect(await counts.next() == 0)
        }
    }

    @Test("""
        Given a queued update the server keeps failing with a server error,
        When tasks are fetched,
        Then the list is still fetched and the update stays queued and shown as pending
        """)
    func serverErrorOnChangeDoesNotBlockFetch() async throws {
        let server = Server()
        try await withDependencies {
            makeDependencies(&$0, server: server)
            $0.taskNetworkClient.updateTask = { _ in throw TaskNetworkError.serverError }
        } operation: {
            let sut = TaskClient.repository
            var task = TaskItem.samples[0]
            task.title = "Edited"
            _ = try await sut.updateTask(task)

            let fetched = try await sut.fetchTasks()

            #expect(server.calls.value == ["fetch"])
            #expect(fetched.first?.title == "Edited")
            #expect(fetched.first?.isPendingSync == true)
            @Dependency(\.taskCacheClient) var cache
            let pending = try await cache.pendingChanges("local")
            #expect(pending.map(\.kind) == [.update])
        }
    }

    @Test("""
        Given a queued create,
        When the fetch is cancelled after the server created the task,
        Then the create is still recorded and the next sync doesn't send it again
        """)
    func cancelAfterCreateDoesNotDuplicate() async throws {
        let server = Server()
        let (created, createdSignal) = AsyncStream<Void>.makeStream()
        let (proceed, proceedSignal) = AsyncStream<Void>.makeStream()
        try await withDependencies {
            makeDependencies(&$0, server: server)
            let network = server.client
            $0.taskNetworkClient.createTask = { body, key in
                let task = try await network.createTask(body, key)
                createdSignal.yield()
                for await _ in proceed { break }
                return task
            }
        } operation: {
            let sut = TaskClient.repository
            server.isOnline.setValue(false)
            _ = try await sut.createTask(TaskDraft(title: "Once"))
            server.isOnline.setValue(true)

            let fetch = Task { try await sut.fetchTasks() }
            for await _ in created { break }
            fetch.cancel()
            proceedSignal.yield()
            _ = await fetch.result

            let synced = try await sut.fetchTasks()

            #expect(server.calls.value.filter { $0.hasPrefix("create") } == ["create Once"])
            #expect(synced.filter { $0.title == "Once" }.count == 1)
            #expect(synced.last?.isPendingSync == false)
        }
    }

    @Test("""
        Given a create the server stored but whose answer was lost,
        When the queued create is synced,
        Then the server returns the stored task for the same key and no duplicate is created
        """)
    func lostAnswerOnCreateIsReplayedNotDuplicated() async throws {
        let server = Server()
        let keys = LockIsolated<[UUID]>([])
        let answerLost = LockIsolated(true)
        try await withDependencies {
            makeDependencies(&$0, server: server)
            let network = server.client
            $0.taskNetworkClient.createTask = { body, key in
                keys.withValue { $0.append(key) }
                let task = try await network.createTask(body, key)
                if answerLost.value {
                    answerLost.setValue(false)
                    throw TaskNetworkError.transport
                }
                return task
            }
        } operation: {
            let sut = TaskClient.repository

            let local = try await sut.createTask(TaskDraft(title: "Once"))
            #expect(local.isPendingSync)
            let synced = try await sut.fetchTasks()

            #expect(keys.value == [local.id, local.id])
            #expect(synced.filter { $0.title == "Once" }.count == 1)
            #expect(synced.last?.isPendingSync == false)
        }
    }

    @Test("""
        Given a create whose answer was lost and a later offline edit of the task,
        When the queued create is synced and the server returns the task as first stored,
        Then the edit follows as an update and the server has the edited task
        """)
    func editAfterLostAnswerIsSentAsUpdate() async throws {
        let server = Server()
        let answerLost = LockIsolated(true)
        try await withDependencies {
            makeDependencies(&$0, server: server)
            let network = server.client
            $0.taskNetworkClient.createTask = { body, key in
                let task = try await network.createTask(body, key)
                if answerLost.value {
                    answerLost.setValue(false)
                    throw TaskNetworkError.transport
                }
                return task
            }
        } operation: {
            let sut = TaskClient.repository
            var local = try await sut.createTask(TaskDraft(title: "Draft"))
            local.title = "Final"
            _ = try await sut.updateTask(local)

            let synced = try await sut.fetchTasks()

            #expect(server.calls.value == ["create Draft", "create Final", "update Final", "fetch"])
            #expect(synced.filter { $0.title == "Final" }.count == 1)
            #expect(synced.contains { $0.title == "Draft" } == false)
            let onServer = try await server.mock.fetchTasks()
            #expect(onServer.last?.title == "Final")
        }
    }
}

