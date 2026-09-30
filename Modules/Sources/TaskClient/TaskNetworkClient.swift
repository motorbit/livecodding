import Dependencies
import DependenciesMacros
import Foundation

/// Network boundary of the Task API: wire DTOs in and out. `TaskClient` maps them to domain types.
///
/// `liveValue` is the in-memory `MockNetworkClient` until a real backend exists. Swap it here,
/// and only here.
@DependencyClient
struct TaskNetworkClient: Sendable {
    var fetchTasks: @Sendable () async throws -> [TaskDTO]
    var createTask: @Sendable (_ body: TaskDraftDTO) async throws -> TaskDTO
    var updateTask: @Sendable (_ body: TaskDTO) async throws -> TaskDTO
    var deleteTask: @Sendable (_ id: UUID) async throws -> Void
}

/// Failures a Task API can report. Mirrors HTTP 400 / 404 / 5xx.
enum TaskNetworkError: Error, Equatable, Sendable {
    case badRequest
    case notFound
    case serverError
}

extension TaskNetworkClient: DependencyKey {
    static let liveValue = TaskNetworkClient.mock(policy: .live)
    static let previewValue = TaskNetworkClient.mock(policy: .instant)
    static let testValue = TaskNetworkClient()
}

extension DependencyValues {
    var taskNetworkClient: TaskNetworkClient {
        get { self[TaskNetworkClient.self] }
        set { self[TaskNetworkClient.self] = newValue }
    }
}
