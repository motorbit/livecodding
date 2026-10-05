import AppEnvironment
import Dependencies
import Foundation
import Logging

/// Live `TaskClient`: calls `\.taskNetworkClient`, maps DTOs to domain values and network
/// failures to `TaskClientError`, and writes every successful result through to
/// `\.taskCacheClient`, scoped to the active environment. Dependencies are resolved per call, so
/// overriding them (tests, previews, an environment switch) is enough.
///
/// Cache writes never fail an operation: the network result is the truth, so a cache error is
/// only logged.
extension TaskClient {
    static let repository = TaskClient(
        fetchTasks: {
            @Dependency(\.taskNetworkClient) var network
            let scope = cacheScope()
            let tasks = try await mapErrors {
                try await network.fetchTasks().map { try $0.toDomain() }
            }
            await updateCache { cache in try await cache.replaceAll(scope, tasks) }
            return tasks
        },
        cachedTasks: {
            @Dependency(\.taskCacheClient) var cache
            return try await logCacheErrors("taskCache.read") {
                try await cache.tasks(cacheScope())
            }
        },
        clearCache: {
            @Dependency(\.taskCacheClient) var cache
            try await logCacheErrors("taskCache.clear") {
                try await cache.clear()
            }
        },
        createTask: { draft in
            @Dependency(\.taskNetworkClient) var network
            let scope = cacheScope()
            let task = try await mapErrors {
                try await network.createTask(TaskDraftDTO(draft)).toDomain()
            }
            await updateCache { cache in try await cache.upsert(scope, task) }
            return task
        },
        updateTask: { task in
            @Dependency(\.taskNetworkClient) var network
            let scope = cacheScope()
            let saved = try await mapErrors {
                try await network.updateTask(TaskDTO(task)).toDomain()
            }
            await updateCache { cache in try await cache.upsert(scope, saved) }
            return saved
        },
        deleteTask: { id in
            @Dependency(\.taskNetworkClient) var network
            let scope = cacheScope()
            try await mapErrors {
                try await network.deleteTask(id)
            }
            await updateCache { cache in try await cache.delete(scope, id) }
        }
    )

    /// Rows are tagged with the environment they came from. The scope is read before the network
    /// call, so a response that arrives after a switch (and after `clearCache`) is filed under the
    /// old environment and never shown in the new one.
    private static func cacheScope() -> String {
        @Dependency(\.environmentClient) var environment
        return environment.current().environment.rawValue
    }

    private static func updateCache(
        _ operation: (TaskCacheClient) async throws -> Void
    ) async {
        @Dependency(\.taskCacheClient) var cache
        do {
            try await operation(cache)
        } catch is CancellationError {
            return
        } catch {
            @Dependency(\.logger) var logger
            logger.error(error, ["operation": "taskCache.write"])
        }
    }

    private static func logCacheErrors<Value>(
        _ operation: String,
        _ body: () async throws -> Value
    ) async throws -> Value {
        do {
            return try await body()
        } catch let error as CancellationError {
            throw error
        } catch {
            @Dependency(\.logger) var logger
            logger.error(error, ["operation": operation])
            throw error
        }
    }

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
            case .serverError, .transport: throw TaskClientError.unavailable
            }
        } catch {
            throw TaskClientError.unavailable
        }
    }
}
