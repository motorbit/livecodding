import Foundation

struct TaskClientLivePolicy: Sendable {
    let readDelay: @Sendable () -> Duration
    let wait: @Sendable (Duration) async throws -> Void
    let shouldFail: @Sendable () -> Bool

    static let live = TaskClientLivePolicy(
        readDelay: { .milliseconds(Int64.random(in: 300...800)) },
        wait: { try await Task.sleep(for: $0) },
        shouldFail: { Double.random(in: 0..<1) < 0.15 }
    )
}

extension TaskClient {
    static func live(policy: TaskClientLivePolicy = .live) -> Self {
        let service = InMemoryTaskService(policy: policy)
        return Self(
            fetchTasks: { try await service.fetchTasks() },
            createTask: { try await service.createTask($0) },
            updateTask: { try await service.updateTask($0) },
            deleteTask: { try await service.deleteTask($0) }
        )
    }
}

private actor InMemoryTaskService {
    private let policy: TaskClientLivePolicy
    private var tasks = TaskItem.samples

    init(policy: TaskClientLivePolicy) {
        self.policy = policy
    }

    func fetchTasks() async throws -> [TaskItem] {
        try await policy.wait(policy.readDelay())
        try failIfRequested()
        return tasks
    }

    func createTask(_ draft: TaskDraft) async throws -> TaskItem {
        try failIfRequested()
        let task = TaskItem(
            id: UUID(),
            title: try normalizedTitle(draft.title),
            notes: draft.notes,
            priority: draft.priority
        )
        tasks.append(task)
        return task
    }

    func updateTask(_ task: TaskItem) async throws -> TaskItem {
        try failIfRequested()
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            throw TaskClientError.unavailable
        }

        var updatedTask = task
        updatedTask.title = try normalizedTitle(task.title)
        tasks[index] = updatedTask
        return updatedTask
    }

    func deleteTask(_ id: UUID) async throws {
        try failIfRequested()
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            throw TaskClientError.unavailable
        }
        tasks.remove(at: index)
    }

    private func failIfRequested() throws {
        guard policy.shouldFail() else { return }
        throw TaskClientError.simulatedFailure
    }

    private func normalizedTitle(_ title: String) throws -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TaskClientError.unavailable }
        return title
    }
}
