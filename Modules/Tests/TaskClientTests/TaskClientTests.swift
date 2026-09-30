import Dependencies
import Foundation
import Testing
@testable import TaskClient

struct TaskClientTests {
    @Test("""
        Given the live client,
        When the seeded tasks are fetched,
        Then the exact samples are returned in insertion order
        """)
    func fetchReturnsOrderedSeedTasks() async throws {
        let sut = makeClient()

        let tasks = try await sut.fetchTasks()

        #expect(tasks == TaskItem.samples)
    }

    @Test("""
        Given the live client,
        When tasks are created, updated and deleted,
        Then insertion order and confirmed values are preserved
        """)
    func createUpdateDeletePreserveOrder() async throws {
        let sut = makeClient()
        let seed = try await sut.fetchTasks()

        let created = try await sut.createTask(
            TaskDraft(title: "  New task  ", notes: "Private notes", priority: .high)
        )
        #expect(created.title == "New task")
        #expect(created.notes == "Private notes")
        #expect(created.priority == .high)
        #expect(created.isComplete == false)
        #expect(created.id != UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)

        var updated = seed[1]
        updated.title = "Updated task"
        updated.isComplete = true
        let saved = try await sut.updateTask(updated)

        let afterUpdate = try await sut.fetchTasks()
        #expect(afterUpdate == [seed[0], saved, seed[2], seed[3], created])

        try await sut.deleteTask(seed[0].id)
        let afterDelete = try await sut.fetchTasks()
        #expect(afterDelete == [saved, seed[2], seed[3], created])
    }

    @Test("""
        Given an injected read delay,
        When tasks are fetched,
        Then the live service invokes it with the selected delay
        """)
    func fetchInvokesInjectedDelay() async throws {
        let delays = LockIsolated<[Duration]>([])
        let policy = TaskClientLivePolicy(
            readDelay: { .milliseconds(475) },
            wait: { duration in delays.withValue { $0.append(duration) } },
            shouldFail: { false }
        )
        let sut = TaskClient.live(policy: policy)

        _ = try await sut.fetchTasks()

        #expect(delays.value == [.milliseconds(475)])
    }

    @Test("""
        Given an injected failure policy,
        When a read and write are attempted,
        Then simulated failures propagate without mutating tasks
        """)
    func injectedFailuresPropagate() async {
        let sut = makeClient(shouldFail: { true })

        await #expect(throws: TaskClientError.simulatedFailure) {
            try await sut.fetchTasks()
        }
        await #expect(throws: TaskClientError.simulatedFailure) {
            try await sut.createTask(TaskDraft(title: "Private task"))
        }
        await #expect(throws: TaskClientError.simulatedFailure) {
            try await sut.updateTask(TaskItem.samples[0])
        }
        await #expect(throws: TaskClientError.simulatedFailure) {
            try await sut.deleteTask(TaskItem.samples[0].id)
        }
    }

    @Test("""
        Given an unknown task or blank title,
        When the live client is asked to mutate it,
        Then it throws the unavailable error
        """)
    func invalidMutationsThrowUnavailable() async {
        let sut = makeClient()

        await #expect(throws: TaskClientError.unavailable) {
            try await sut.createTask(TaskDraft(title: " \n\t "))
        }
        await #expect(throws: TaskClientError.unavailable) {
            try await sut.updateTask(TaskItem(id: UUID(), title: "Missing", priority: .low))
        }
        await #expect(throws: TaskClientError.unavailable) {
            try await sut.deleteTask(UUID())
        }
    }

    private func makeClient(shouldFail: @escaping @Sendable () -> Bool = { false }) -> TaskClient {
        TaskClient.live(
            policy: TaskClientLivePolicy(
                readDelay: { .milliseconds(300) },
                wait: { _ in },
                shouldFail: shouldFail
            )
        )
    }
}
