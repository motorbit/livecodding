import AppEnvironment
import Dependencies
import Foundation
import Logging

/// Live `TaskClient`: calls `\.taskNetworkClient`, maps DTOs to domain values and network
/// failures to `TaskClientError`, and writes every successful result through to
/// `\.taskCacheClient`, scoped to the active environment. Dependencies are resolved per call, so
/// overriding them (tests, previews, an environment switch) is enough.
///
/// Cache writes never fail an online operation: the network result is the truth, so a cache error
/// is only logged. Offline, the queue is the only copy of the change, so failing to queue it
/// throws the original `.unavailable`.
extension TaskClient {
    static let repository = TaskClient(
        fetchTasks: {
            @Dependency(\.taskNetworkClient) var network
            let scope = cacheScope()
            try await syncPendingChanges(scope: scope)
            let tasks = try await mapErrors {
                try await network.fetchTasks().map { try $0.toDomain() }
            }
            await updateCache { cache in try await cache.replaceAll(scope, tasks) }
            return await applyingPendingChanges(to: tasks, scope: scope)
        },
        cachedTasks: {
            @Dependency(\.taskCacheClient) var cache
            let scope = cacheScope()
            return try await logCacheErrors("taskCache.read") {
                PendingChanges.apply(
                    try await cache.pendingChanges(scope),
                    to: try await cache.tasks(scope)
                )
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
            @Dependency(\.uuid) var uuid
            let scope = cacheScope()
            // One id for both paths: it is the request's idempotency key and, if the request
            // fails, the queued task's local id. A create that reached the server but whose
            // answer was lost is then replayed by the sync instead of duplicated.
            let localID = uuid()
            do {
                let task = try await mapErrors {
                    try await network.createTask(TaskDraftDTO(draft), localID).toDomain()
                }
                await updateCache { cache in try await cache.upsert(scope, task) }
                return task
            } catch TaskClientError.unavailable {
                let task = TaskItem(
                    id: localID,
                    title: try validatedTitle(draft.title),
                    notes: draft.notes,
                    priority: draft.priority,
                    dueDate: draft.dueDate,
                    isPendingSync: true
                )
                try await enqueue(.create(task), scope: scope)
                return task
            }
        },
        updateTask: { task in
            @Dependency(\.taskNetworkClient) var network
            let scope = cacheScope()
            var queued = task
            queued.title = try validatedTitle(task.title)
            queued.isPendingSync = true
            let resolved = await resolve(task.id, scope: scope)
            guard !resolved.hasPendingChange else {
                try await enqueue(.update(queued), scope: scope)
                return queued
            }
            let request = TaskItem(
                id: resolved.id,
                title: task.title,
                notes: task.notes,
                priority: task.priority,
                isComplete: task.isComplete,
                dueDate: task.dueDate
            )
            do {
                let saved = try await mapErrors {
                    try await network.updateTask(TaskDTO(request)).toDomain()
                }
                await updateCache { cache in try await cache.upsert(scope, saved) }
                return TaskItem(
                    id: task.id,
                    title: saved.title,
                    notes: saved.notes,
                    priority: saved.priority,
                    isComplete: saved.isComplete,
                    dueDate: saved.dueDate
                )
            } catch TaskClientError.unavailable {
                try await enqueue(.update(queued), scope: scope)
                return queued
            }
        },
        deleteTask: { id in
            @Dependency(\.taskNetworkClient) var network
            let scope = cacheScope()
            let resolved = await resolve(id, scope: scope)
            guard !resolved.hasPendingChange else {
                try await enqueue(.delete(id), scope: scope)
                return
            }
            do {
                try await mapErrors {
                    try await network.deleteTask(resolved.id)
                }
                await updateCache { cache in try await cache.delete(scope, resolved.id) }
            } catch TaskClientError.unavailable {
                try await enqueue(.delete(id), scope: scope)
            }
        },
        pendingSyncCounts: {
            @Dependency(\.taskCacheClient) var cache
            return cache.pendingChangeCounts(cacheScope())
        }
    )

    /// Rows are tagged with the environment they came from. The scope is read before the network
    /// call, so a response that arrives after a switch (and after `clearCache`) is filed under the
    /// old environment and never shown in the new one.
    static func cacheScope() -> String {
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

    static func logCacheErrors<Value>(
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

    static func mapErrors<Value>(
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
