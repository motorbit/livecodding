import Dependencies
import Foundation
import Logging

/// Offline changes: queueing, sending the queue and showing queued changes on top of the saved
/// list. Conflict policy is last write wins: a queued change is sent as is, whatever the server
/// has. A change the server refuses (validation or not found) is dropped and logged; the fetch that
/// follows the sync brings back the server's version.
extension TaskClient {
    /// The most passes one sync makes. A change edited while being sent stays queued for another
    /// pass; the limit keeps a user who edits faster than the server answers from pinning the sync.
    private static let maxSyncPasses = 3

    /// Sends every queued change, oldest first. Stops at the first change the server can't take
    /// now (`.unavailable`), leaving it and the rest queued; the fetch that follows decides
    /// whether the server is down, so one change the server keeps failing never blocks the list.
    /// A broken cache is logged and skipped. Only cancellation is thrown, and only between
    /// changes.
    static func syncPendingChanges(scope: String) async throws {
        @Dependency(\.taskCacheClient) var cache
        do {
            try await cache.serialized {
                for _ in 0..<maxSyncPasses {
                    let changes = try await cache.pendingChanges(scope)
                    guard !changes.isEmpty else { return }
                    for change in changes {
                        try Task.checkCancellation()
                        let settle = cache.settle
                        // Not cancellable by the caller: once a request is out, its result must
                        // be recorded, or a create would be sent again by the next sync.
                        try await Task {
                            try await settle(scope, change, send(change))
                        }.value
                    }
                }
            }
        } catch let error as CancellationError {
            throw error
        } catch TaskClientError.unavailable {
            return
        } catch {
            @Dependency(\.logger) var logger
            logger.error(error, ["operation": "taskSync"])
        }
    }

    private static func send(_ change: PendingChange) async throws -> SyncOutcome {
        @Dependency(\.taskNetworkClient) var network
        do {
            switch change.kind {
            case .create:
                guard let task = change.task else { return rejected(change, reason: "unreadable") }
                let created = try await mapErrors {
                    try await network.createTask(TaskDraftDTO(TaskDraft(
                        title: task.title,
                        notes: task.notes,
                        priority: task.priority,
                        dueDate: task.dueDate
                    )), change.taskID).toDomain()
                }
                var desired = created
                desired.title = task.title
                desired.notes = task.notes
                desired.priority = task.priority
                desired.isComplete = task.isComplete
                desired.dueDate = task.dueDate
                // A create can't carry completion, and a replayed key returns the task as first
                // stored, without edits queued since; either way the queued values follow as an
                // update.
                guard TaskDTO(desired) != TaskDTO(created) else { return .created(created) }
                do {
                    return .created(try await mapErrors {
                        try await network.updateTask(TaskDTO(desired)).toDomain()
                    })
                } catch is TaskClientError {
                    // The task exists on the server now: record it and leave the values queued.
                    return .createdNeedingUpdate(created)
                }
            case .update:
                guard let task = change.task else { return rejected(change, reason: "unreadable") }
                return .updated(try await mapErrors {
                    try await network.updateTask(TaskDTO(task)).toDomain()
                })
            case .delete:
                // Created and deleted offline: the server never knew it.
                guard !change.isLocal else { return .deleted }
                try await mapErrors { try await network.deleteTask(change.taskID) }
                return .deleted
            }
        } catch TaskClientError.validation {
            return rejected(change, reason: "validation")
        } catch TaskClientError.notFound {
            switch change.kind {
            case .delete: return .deleted
            case .create, .update: return rejected(change, reason: "notFound")
            }
        }
    }

    private static func rejected(_ change: PendingChange, reason: String) -> SyncOutcome {
        @Dependency(\.logger) var logger
        logger.warning("Dropped a queued change the server refused", [
            "operation": "taskSync.rejected",
            "kind": change.kind.rawValue,
            "reason": reason,
        ])
        return .rejected
    }

    /// `tasks` with queued changes applied. Without a readable queue the server list is returned
    /// as is.
    static func applyingPendingChanges(to tasks: [TaskItem], scope: String) async -> [TaskItem] {
        @Dependency(\.taskCacheClient) var cache
        do {
            return PendingChanges.apply(try await cache.pendingChanges(scope), to: tasks)
        } catch {
            @Dependency(\.logger) var logger
            logger.error(error, ["operation": "taskCache.read"])
            return tasks
        }
    }

    /// Without a readable cache, a task is treated as having no queued change: it goes to the
    /// network directly, which is what happened before offline support.
    static func resolve(_ id: UUID, scope: String) async -> ResolvedTaskID {
        @Dependency(\.taskCacheClient) var cache
        do {
            return try await cache.resolve(scope, id)
        } catch {
            @Dependency(\.logger) var logger
            logger.error(error, ["operation": "taskCache.read"])
            return ResolvedTaskID(id: id, hasPendingChange: false)
        }
    }

    /// The queue is the only copy of an offline change, so if it can't be written the caller
    /// gets the original `.unavailable`.
    static func enqueue(_ change: LocalChange, scope: String) async throws {
        @Dependency(\.taskCacheClient) var cache
        do {
            try await cache.enqueue(scope, change)
        } catch let error as CancellationError {
            throw error
        } catch {
            @Dependency(\.logger) var logger
            logger.error(error, ["operation": "taskCache.enqueue"])
            throw TaskClientError.unavailable
        }
    }

    /// The server's rule (trimmed, not blank), checked locally so an offline change can't be one
    /// the server will refuse.
    static func validatedTitle(_ title: String) throws(TaskClientError) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .validation }
        return trimmed
    }
}

enum PendingChanges {
    /// Queued changes on top of the saved list: updates replace in place, creates append (in queue
    /// order), deletes remove. Changed tasks have `isPendingSync`. An update to a task that isn't
    /// in the list is skipped; the sync will find out whether it still exists.
    static func apply(_ changes: [PendingChange], to tasks: [TaskItem]) -> [TaskItem] {
        var tasks = tasks
        for change in changes {
            let index = tasks.firstIndex { $0.id == change.taskID }
            switch change.kind {
            case .create:
                guard let task = change.task else { continue }
                if let index { tasks[index] = task } else { tasks.append(task) }
            case .update:
                guard let task = change.task, let index else { continue }
                tasks[index] = task
            case .delete:
                if let index { tasks.remove(at: index) }
            }
        }
        return tasks
    }
}
