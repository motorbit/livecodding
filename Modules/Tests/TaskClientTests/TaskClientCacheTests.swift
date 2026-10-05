import AppEnvironment
import Dependencies
import Foundation
import Testing
@testable import TaskClient

private func makeDependencies(_ dependencies: inout DependencyValues) {
    dependencies.environmentClient.current = { EnvironmentConfig(environment: .local, apiBackend: .mock) }
    dependencies.taskCacheClient = .inMemory()
    dependencies.taskNetworkClient = .mock(policy: .instant)
}

private struct TestError: Error {}

struct TaskClientCacheTests {
    @Test("""
        Given an empty cache,
        When tasks are fetched, created, updated and deleted,
        Then cachedTasks mirrors the server list in order
        """)
    func writesThroughEverySuccessfulCall() async throws {
        try await withDependencies { makeDependencies(&$0) } operation: {
            let sut = TaskClient.repository
            #expect(try await sut.cachedTasks().isEmpty)

            let seed = try await sut.fetchTasks()
            #expect(try await sut.cachedTasks() == seed)

            let created = try await sut.createTask(TaskDraft(title: "New", priority: .high))
            var updated = seed[1]
            updated.isComplete = true
            _ = try await sut.updateTask(updated)
            try await sut.deleteTask(seed[0].id)

            #expect(try await sut.cachedTasks() == [updated, seed[2], seed[3], created])
        }
    }

    @Test("""
        Given tasks cached in the local environment,
        When the active environment is dev,
        Then its cache is separate and starts empty
        """)
    func cacheIsScopedPerEnvironment() async throws {
        let environment = LockIsolated(AppEnvironment.local)
        try await withDependencies {
            makeDependencies(&$0)
            $0.environmentClient.current = {
                EnvironmentConfig(environment: environment.value, apiBackend: .mock)
            }
        } operation: {
            let sut = TaskClient.repository
            let local = try await sut.fetchTasks()

            environment.setValue(.dev)
            #expect(try await sut.cachedTasks().isEmpty)

            environment.setValue(.local)
            #expect(try await sut.cachedTasks() == local)
        }
    }

    @Test("""
        Given a fetch in flight in the local environment,
        When the environment switches to dev before the response arrives,
        Then the result is cached under local and dev stays empty
        """)
    func scopeIsFixedBeforeTheNetworkCall() async throws {
        let environment = LockIsolated(AppEnvironment.local)
        try await withDependencies {
            makeDependencies(&$0)
            $0.environmentClient.current = {
                EnvironmentConfig(environment: environment.value, apiBackend: .mock)
            }
            $0.taskNetworkClient.fetchTasks = {
                environment.setValue(.dev)
                return TaskItem.samples.map { TaskDTO($0) }
            }
        } operation: {
            let sut = TaskClient.repository
            _ = try await sut.fetchTasks()

            #expect(try await sut.cachedTasks().isEmpty)
            environment.setValue(.local)
            #expect(try await sut.cachedTasks() == TaskItem.samples)
        }
    }

    @Test("""
        Given cached tasks,
        When the cache is cleared,
        Then cachedTasks is empty
        """)
    func clearCacheEmptiesIt() async throws {
        try await withDependencies { makeDependencies(&$0) } operation: {
            let sut = TaskClient.repository
            _ = try await sut.fetchTasks()

            try await sut.clearCache()

            #expect(try await sut.cachedTasks().isEmpty)
        }
    }

    @Test("""
        Given a cache that can't be read,
        When cached tasks are requested,
        Then the error is logged and rethrown
        """)
    func cacheReadFailureIsLogged() async {
        let logged = LockIsolated<[String]>([])
        await withDependencies {
            makeDependencies(&$0)
            $0.taskCacheClient.tasks = { _ in throw TestError() }
            $0.logger.logError = { _, metadata in
                logged.withValue { $0.append(metadata["operation"] ?? "") }
            }
        } operation: {
            await #expect(throws: TestError.self) { try await TaskClient.repository.cachedTasks() }
        }
        #expect(logged.value == ["taskCache.read"])
    }

    @Test("""
        Given a cached list,
        When the network fails,
        Then the error is thrown and the cache is unchanged
        """)
    func failedNetworkKeepsCache() async throws {
        let fails = LockIsolated(false)
        try await withDependencies {
            makeDependencies(&$0)
            $0.taskNetworkClient.fetchTasks = {
                if fails.value { throw TaskNetworkError.transport }
                return TaskItem.samples.map { TaskDTO($0) }
            }
        } operation: {
            let sut = TaskClient.repository
            _ = try await sut.fetchTasks()
            fails.setValue(true)

            await #expect(throws: TaskClientError.unavailable) { try await sut.fetchTasks() }
            #expect(try await sut.cachedTasks() == TaskItem.samples)
        }
    }

    @Test("""
        Given a cache that fails to write,
        When tasks are fetched,
        Then the fetch still succeeds and the cache error is logged
        """)
    func cacheWriteFailureIsLoggedNotThrown() async throws {
        let logged = LockIsolated<[String]>([])
        try await withDependencies {
            makeDependencies(&$0)
            $0.taskCacheClient.replaceAll = { _, _ in throw TestError() }
            $0.logger.logError = { _, metadata in
                logged.withValue { $0.append(metadata["operation"] ?? "") }
            }
        } operation: {
            let tasks = try await TaskClient.repository.fetchTasks()
            #expect(tasks == TaskItem.samples)
        }
        #expect(logged.value == ["taskCache.write"])
    }
}
