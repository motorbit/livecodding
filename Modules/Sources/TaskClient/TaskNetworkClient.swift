import AppEnvironment
import Dependencies
import DependenciesMacros
import Foundation
import Logging

/// Network boundary of the Task API: wire DTOs in and out. `TaskClient` maps them to domain types.
///
/// `liveValue` picks the backend per call from the active environment (`\.environmentClient`):
/// the in-memory `MockNetworkClient` for `.mock`, HTTP (`TaskNetworkClient+HTTP.swift`) for
/// `.remote`. This is the only place that decides it.
@DependencyClient
struct TaskNetworkClient: Sendable {
    var fetchTasks: @Sendable () async throws -> [TaskDTO]
    /// `idempotencyKey` makes the call safe to repeat: a server that has already created a task
    /// for the key returns that task instead of creating another.
    var createTask: @Sendable (_ body: TaskDraftDTO, _ idempotencyKey: UUID) async throws -> TaskDTO
    /// With `ifMatch`, the server applies the change only to that version of the task and throws
    /// `.conflict` otherwise. `nil` means last write wins.
    var updateTask: @Sendable (_ body: TaskDTO, _ ifMatch: Int?) async throws -> TaskDTO
    var deleteTask: @Sendable (_ id: UUID, _ ifMatch: Int?) async throws -> Void
}

/// Failures a Task API can report. Mirrors HTTP 400 / 404 / 5xx, plus `transport` when there's
/// no usable HTTP response (offline, server down, undecodable body).
enum TaskNetworkError: Error, Equatable, Sendable {
    case badRequest
    case notFound
    /// HTTP 412: the task has a version other than `ifMatch`.
    case conflict
    case serverError
    case transport
}

extension TaskNetworkClient: DependencyKey {
    static let liveValue = TaskNetworkClient.environmentBacked(mock: .mock(policy: .live))
    static let previewValue = TaskNetworkClient.mock(policy: .instant)
    static let testValue = TaskNetworkClient()
}

extension DependencyValues {
    var taskNetworkClient: TaskNetworkClient {
        get { self[TaskNetworkClient.self] }
        set { self[TaskNetworkClient.self] = newValue }
    }
}

extension TaskNetworkClient {
    /// Resolves the backend on every call, so an environment switch applies to the next request.
    /// `mock` is created once and shared, so its in-memory tasks survive between calls.
    static func environmentBacked(mock: TaskNetworkClient) -> Self {
        @Sendable func backend() throws -> TaskNetworkClient {
            @Dependency(\.environmentClient) var environment
            let config = environment.current()
            switch config.apiBackend {
            case .mock:
                return mock
            case .remote(let baseURL):
                return .http(baseURL: baseURL)
            case .notConfigured:
                @Dependency(\.logger) var logger
                let error = EnvironmentError.apiBaseURLMissing(config.environment)
                logger.error(error, ["environment": config.environment.rawValue])
                throw error
            }
        }
        return Self(
            fetchTasks: { try await backend().fetchTasks() },
            createTask: { try await backend().createTask($0, $1) },
            updateTask: { try await backend().updateTask($0, $1) },
            deleteTask: { try await backend().deleteTask($0, $1) }
        )
    }
}
