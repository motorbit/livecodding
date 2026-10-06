import AppEnvironment
import Dependencies
import Foundation
import Testing
@testable import TaskClient

private func makeDependencies(_ dependencies: inout DependencyValues) {
    dependencies.environmentClient.current = { EnvironmentConfig(environment: .local, apiBackend: .mock) }
    dependencies.taskCacheClient = .inMemory()
    dependencies.uuid = .incrementing
}

struct TaskClientTests {
    @Test("""
        Given the repository over the instant mock network,
        When tasks are fetched, created, updated and deleted,
        Then domain values round-trip and order is preserved
        """)
    func repositoryRoundTripsThroughMockNetwork() async throws {
        try await withDependencies {
            makeDependencies(&$0)
            $0.taskNetworkClient = .mock(policy: .instant)
        } operation: {
            let sut = TaskClient.repository
            let dueDate = utcDay(2026, 10, 1)

            let seed = try await sut.fetchTasks()
            #expect(seed == TaskItem.samples)

            let created = try await sut.createTask(
                TaskDraft(title: "  New task  ", notes: "Notes", priority: .high, dueDate: dueDate)
            )
            #expect(created.title == "New task")
            #expect(created.priority == .high)
            #expect(created.dueDate == dueDate)
            #expect(created.isComplete == false)

            var updated = seed[1]
            updated.isComplete = true
            let saved = try await sut.updateTask(updated)
            #expect(saved == updated)

            try await sut.deleteTask(seed[0].id)
            #expect(try await sut.fetchTasks() == [saved, seed[2], seed[3], created])
        }
    }

    @Test("""
        Given each network failure,
        When tasks are fetched,
        Then it maps to the matching TaskClientError
        """,
        arguments: [
            (TaskNetworkError.badRequest, TaskClientError.validation),
            (.notFound, .notFound),
            (.serverError, .unavailable),
            (.transport, .unavailable),
        ])
    func mapsFetchErrors(networkError: TaskNetworkError, expected: TaskClientError) async {
        await withDependencies {
            makeDependencies(&$0)
            $0.taskNetworkClient.fetchTasks = { throw networkError }
        } operation: {
            await #expect(throws: expected) { try await TaskClient.repository.fetchTasks() }
        }
    }

    @Test("""
        Given the server refuses a change,
        When a task is created, updated or deleted,
        Then the matching TaskClientError is thrown and nothing is queued
        """,
        arguments: [
            (TaskNetworkError.badRequest, TaskClientError.validation),
            (.notFound, .notFound),
        ])
    func mapsMutationErrors(networkError: TaskNetworkError, expected: TaskClientError) async throws {
        try await withDependencies {
            makeDependencies(&$0)
            $0.taskNetworkClient.createTask = { _, _ in throw networkError }
            $0.taskNetworkClient.updateTask = { _ in throw networkError }
            $0.taskNetworkClient.deleteTask = { _ in throw networkError }
        } operation: {
            let sut = TaskClient.repository
            await #expect(throws: expected) { try await sut.createTask(TaskDraft(title: "T")) }
            await #expect(throws: expected) { try await sut.updateTask(TaskItem.samples[0]) }
            await #expect(throws: expected) { try await sut.deleteTask(TaskItem.samples[0].id) }
            @Dependency(\.taskCacheClient) var cache
            let pending = try await cache.pendingChanges("local")
            #expect(pending.isEmpty)
        }
    }

    @Test("""
        Given the network returns a malformed due date,
        When tasks are fetched,
        Then the repository throws unavailable
        """)
    func malformedResponseMapsToUnavailable() async {
        await withDependencies {
            makeDependencies(&$0)
            $0.taskNetworkClient.fetchTasks = {
                [TaskDTO(id: UUID(), title: "Bad", notes: "", priority: .low, done: false, dueDate: "nope")]
            }
        } operation: {
            await #expect(throws: TaskClientError.unavailable) {
                try await TaskClient.repository.fetchTasks()
            }
        }
    }

    @Test("""
        Given the network call is cancelled,
        When the repository maps errors,
        Then CancellationError propagates unchanged
        """)
    func cancellationPropagates() async {
        await withDependencies {
            makeDependencies(&$0)
            $0.taskNetworkClient.fetchTasks = { throw CancellationError() }
        } operation: {
            await #expect(throws: CancellationError.self) {
                try await TaskClient.repository.fetchTasks()
            }
        }
    }

    private func utcDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
