import Foundation

/// Latency and failure behaviour of `MockNetworkClient`. Injected so tests never sleep or flake.
struct MockNetworkPolicy: Sendable {
    var readDelay: @Sendable () -> Duration
    var writeDelay: @Sendable () -> Duration
    var wait: @Sendable (Duration) async throws -> Void
    var shouldFail: @Sendable () -> Bool

    /// Challenge behaviour: reads 300–800 ms, writes 100–300 ms, ~15 % failures.
    static let live = MockNetworkPolicy(
        readDelay: { .milliseconds(Int64.random(in: 300...800)) },
        writeDelay: { .milliseconds(Int64.random(in: 100...300)) },
        wait: { try await Task.sleep(for: $0) },
        shouldFail: { Double.random(in: 0..<1) < 0.15 }
    )

    /// No latency, no failures. For previews and deterministic tests.
    static let instant = MockNetworkPolicy(
        readDelay: { .zero },
        writeDelay: { .zero },
        wait: { _ in },
        shouldFail: { false }
    )
}

/// In-memory stand-in for the Task backend. Behaves like a remote API: async, delayed, can fail,
/// owns IDs, validates input and trims titles.
actor MockNetworkClient {
    private let policy: MockNetworkPolicy
    private var tasks: [TaskDTO]

    init(policy: MockNetworkPolicy, seeds: [TaskDTO] = MockNetworkClient.seedTasks()) {
        self.policy = policy
        self.tasks = seeds
    }

    func fetchTasks() async throws -> [TaskDTO] {
        try await simulate(policy.readDelay())
        return tasks
    }

    func createTask(_ body: TaskDraftDTO) async throws -> TaskDTO {
        try await simulate(policy.writeDelay())
        let task = TaskDTO(
            id: UUID(),
            title: try validatedTitle(body.title),
            notes: body.notes,
            priority: body.priority,
            done: false,
            dueDate: body.dueDate
        )
        tasks.append(task)
        return task
    }

    func updateTask(_ body: TaskDTO) async throws -> TaskDTO {
        try await simulate(policy.writeDelay())
        guard let index = tasks.firstIndex(where: { $0.id == body.id }) else {
            throw TaskNetworkError.notFound
        }
        var task = body
        task.title = try validatedTitle(body.title)
        tasks[index] = task
        return task
    }

    func deleteTask(_ id: UUID) async throws {
        try await simulate(policy.writeDelay())
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            throw TaskNetworkError.notFound
        }
        tasks.remove(at: index)
    }

    private func simulate(_ delay: Duration) async throws {
        try await policy.wait(delay)
        if policy.shouldFail() { throw TaskNetworkError.serverError }
    }

    private func validatedTitle(_ title: String) throws -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TaskNetworkError.badRequest }
        return title
    }
}

// MARK: - Seeds

extension MockNetworkClient {
    /// The challenge's example tasks from `Resources/seed-tasks.json`, with stable IDs
    /// `00000000-0000-0000-0000-00000000000N` (1-based).
    static func seedTasks() -> [TaskDTO] {
        guard let url = Bundle.module.url(forResource: "seed-tasks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let seeds = try? JSONDecoder().decode([SeedTaskDTO].self, from: data) else {
            preconditionFailure("TaskClient: bundled seed-tasks.json is missing or malformed")
        }
        return seeds.enumerated().map { offset, seed in
            TaskDTO(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", offset + 1))!,
                title: seed.title,
                notes: seed.notes,
                priority: seed.priority,
                done: seed.done,
                dueDate: nil
            )
        }
    }
}

private struct SeedTaskDTO: Decodable {
    var title: String
    var notes: String
    var priority: PriorityDTO
    var done: Bool
}

// MARK: - Client

extension TaskNetworkClient {
    static func mock(policy: MockNetworkPolicy) -> Self {
        let network = MockNetworkClient(policy: policy)
        return Self(
            fetchTasks: { try await network.fetchTasks() },
            createTask: { try await network.createTask($0) },
            updateTask: { try await network.updateTask($0) },
            deleteTask: { try await network.deleteTask($0) }
        )
    }
}
