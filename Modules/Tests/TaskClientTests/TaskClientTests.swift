import Dependencies
import Foundation
import Testing
@testable import TaskClient

struct TaskClientTests {
    @Test("""
        Given the repository over the instant mock network,
        When tasks are fetched, created, updated and deleted,
        Then domain values round-trip and order is preserved
        """)
    func repositoryRoundTripsThroughMockNetwork() async throws {
        try await withDependencies {
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
        When the repository calls the network,
        Then it maps to the matching TaskClientError
        """,
        arguments: [
            (TaskNetworkError.badRequest, TaskClientError.validation),
            (.notFound, .notFound),
            (.serverError, .unavailable),
            (.transport, .unavailable),
        ])
    func mapsNetworkErrors(networkError: TaskNetworkError, expected: TaskClientError) async {
        await withDependencies {
            $0.taskNetworkClient.fetchTasks = { throw networkError }
            $0.taskNetworkClient.createTask = { _ in throw networkError }
            $0.taskNetworkClient.updateTask = { _ in throw networkError }
            $0.taskNetworkClient.deleteTask = { _ in throw networkError }
        } operation: {
            let sut = TaskClient.repository
            await #expect(throws: expected) { try await sut.fetchTasks() }
            await #expect(throws: expected) { try await sut.createTask(TaskDraft(title: "T")) }
            await #expect(throws: expected) { try await sut.updateTask(TaskItem.samples[0]) }
            await #expect(throws: expected) { try await sut.deleteTask(TaskItem.samples[0].id) }
        }
    }

    @Test("""
        Given the network returns a malformed due date,
        When tasks are fetched,
        Then the repository throws unavailable
        """)
    func malformedResponseMapsToUnavailable() async {
        await withDependencies {
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
