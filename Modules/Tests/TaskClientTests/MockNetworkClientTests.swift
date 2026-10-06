import Dependencies
import Foundation
import Testing
@testable import TaskClient

struct MockNetworkClientTests {
    @Test("""
        Given the bundled seed JSON,
        When the mock network is fetched,
        Then it returns the challenge tasks with stable IDs, matching TaskItem.samples
        """)
    func seedsMatchChallengeExamples() async throws {
        let sut = MockNetworkClient(policy: .instant)

        let tasks = try await sut.fetchTasks()

        #expect(try tasks.map { try $0.toDomain() } == TaskItem.samples)
        #expect(tasks.map(\.priority) == [.high, .medium, .low, .medium])
        #expect(tasks.map(\.done) == [false, false, true, false])
    }

    @Test("""
        Given recorded delays,
        When a read and each write run,
        Then reads wait the read delay and writes wait the write delay
        """)
    func readsAndWritesUseTheirDelays() async throws {
        let waits = LockIsolated<[Duration]>([])
        let sut = MockNetworkClient(policy: MockNetworkPolicy(
            readDelay: { .milliseconds(500) },
            writeDelay: { .milliseconds(150) },
            wait: { duration in waits.withValue { $0.append(duration) } },
            shouldFail: { false }
        ))

        let seed = try await sut.fetchTasks()
        let created = try await sut.createTask(TaskDraftDTO(title: "New", notes: "", priority: .low), idempotencyKey: UUID())
        _ = try await sut.updateTask(seed[0])
        try await sut.deleteTask(created.id)

        #expect(waits.value == [
            .milliseconds(500), .milliseconds(150), .milliseconds(150), .milliseconds(150),
        ])
    }

    @Test("""
        Given the mock network,
        When tasks are created, updated and deleted,
        Then it assigns IDs, trims titles, starts tasks incomplete and preserves order
        """)
    func crudPreservesOrderAndNormalizes() async throws {
        let sut = MockNetworkClient(policy: .instant)
        let seed = try await sut.fetchTasks()

        let created = try await sut.createTask(
            TaskDraftDTO(title: "  New task  ", notes: "Notes", priority: .high, dueDate: "2026-10-01"),
            idempotencyKey: UUID()
        )
        #expect(created.title == "New task")
        #expect(created.done == false)
        #expect(created.dueDate == "2026-10-01")
        #expect(!seed.map(\.id).contains(created.id))

        var edited = seed[1]
        edited.title = " Edited "
        edited.done = true
        let saved = try await sut.updateTask(edited)
        #expect(saved.title == "Edited")

        try await sut.deleteTask(seed[0].id)

        #expect(try await sut.fetchTasks() == [saved, seed[2], seed[3], created])
    }

    @Test("""
        Given a blank title or unknown ID,
        When the mock network mutates,
        Then it throws badRequest or notFound
        """)
    func invalidRequestsThrowTypedErrors() async {
        let sut = MockNetworkClient(policy: .instant)

        await #expect(throws: TaskNetworkError.badRequest) {
            try await sut.createTask(TaskDraftDTO(title: " \n\t ", notes: "", priority: .low), idempotencyKey: UUID())
        }
        await #expect(throws: TaskNetworkError.notFound) {
            try await sut.updateTask(TaskDTO(id: UUID(), title: "Missing", notes: "", priority: .low, done: false))
        }
        await #expect(throws: TaskNetworkError.notFound) {
            try await sut.deleteTask(UUID())
        }
    }

    @Test("""
        Given a policy that always fails,
        When a read and every write are attempted,
        Then each throws serverError and no data changes
        """)
    func failuresThrowServerErrorWithoutMutating() async throws {
        let failing = LockIsolated(true)
        let sut = MockNetworkClient(policy: MockNetworkPolicy(
            readDelay: { .zero },
            writeDelay: { .zero },
            wait: { _ in },
            shouldFail: { failing.value }
        ))
        let seedID = TaskItem.samples[0].id

        await #expect(throws: TaskNetworkError.serverError) { try await sut.fetchTasks() }
        await #expect(throws: TaskNetworkError.serverError) {
            try await sut.createTask(TaskDraftDTO(title: "New", notes: "", priority: .low), idempotencyKey: UUID())
        }
        await #expect(throws: TaskNetworkError.serverError) {
            try await sut.updateTask(TaskDTO(id: seedID, title: "Changed", notes: "", priority: .low, done: true))
        }
        await #expect(throws: TaskNetworkError.serverError) { try await sut.deleteTask(seedID) }

        failing.setValue(false)
        #expect(try await sut.fetchTasks() == MockNetworkClient.seedTasks())
    }

    @Test("""
        Given a task created with an idempotency key,
        When the same key is sent again,
        Then the first task is returned and nothing new is created, or notFound once it is deleted
        """)
    func repeatedIdempotencyKeyReturnsFirstTask() async throws {
        let sut = MockNetworkClient(policy: .instant)
        let key = UUID()

        let first = try await sut.createTask(TaskDraftDTO(title: "Once", notes: "", priority: .low), idempotencyKey: key)
        let again = try await sut.createTask(TaskDraftDTO(title: "Twice", notes: "", priority: .low), idempotencyKey: key)

        #expect(again == first)
        #expect(try await sut.fetchTasks().count == 5)
        try await sut.deleteTask(first.id)
        await #expect(throws: TaskNetworkError.notFound) {
            try await sut.createTask(TaskDraftDTO(title: "Once", notes: "", priority: .low), idempotencyKey: key)
        }
    }

    @Test("""
        Given a seeded task at version 1,
        When it is updated with If-Match 1, then updated and deleted with that stale version,
        Then the update bumps the version to 2 and the stale calls throw conflict without changes
        """)
    func ifMatchChecksVersion() async throws {
        let sut = MockNetworkClient(policy: .instant)
        var task = try #require(try await sut.fetchTasks().first)
        #expect(task.version == 1)
        task.title = "Changed"

        let saved = try await sut.updateTask(task, ifMatch: 1)

        #expect(saved.version == 2)
        await #expect(throws: TaskNetworkError.conflict) { try await sut.updateTask(task, ifMatch: 1) }
        await #expect(throws: TaskNetworkError.conflict) { try await sut.deleteTask(task.id, ifMatch: 1) }
        #expect(try await sut.fetchTasks().first == saved)
        try await sut.deleteTask(task.id, ifMatch: 2)
        #expect(try await sut.fetchTasks().count == 3)
    }
}
