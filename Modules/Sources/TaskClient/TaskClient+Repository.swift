import Dependencies
import Foundation

/// Live `TaskClient`: calls `\.taskNetworkClient`, maps DTOs to domain values and network
/// failures to `TaskClientError`. The network client is resolved per call, so overriding
/// `\.taskNetworkClient` (tests, previews, a future real backend) is enough.
extension TaskClient {
    static let repository = TaskClient(
        fetchTasks: {
            @Dependency(\.taskNetworkClient) var network
            return try await mapErrors {
                try await network.fetchTasks().map { try $0.toDomain() }
            }
        },
        createTask: { draft in
            @Dependency(\.taskNetworkClient) var network
            return try await mapErrors {
                try await network.createTask(TaskDraftDTO(draft)).toDomain()
            }
        },
        updateTask: { task in
            @Dependency(\.taskNetworkClient) var network
            return try await mapErrors {
                try await network.updateTask(TaskDTO(task)).toDomain()
            }
        },
        deleteTask: { id in
            @Dependency(\.taskNetworkClient) var network
            try await mapErrors {
                try await network.deleteTask(id)
            }
        }
    )

    private static func mapErrors<Value>(
        _ operation: () async throws -> Value
    ) async throws -> Value {
        do {
            return try await operation()
        } catch let error as CancellationError {
            throw error
        } catch let error as TaskClientError {
            throw error
        } catch let error as TaskNetworkError {
            switch error {
            case .badRequest: throw TaskClientError.validation
            case .notFound: throw TaskClientError.notFound
            case .serverError: throw TaskClientError.unavailable
            }
        } catch {
            throw TaskClientError.unavailable
        }
    }
}
