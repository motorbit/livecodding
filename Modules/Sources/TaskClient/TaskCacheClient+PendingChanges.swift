import Foundation
import GRDB

/// Row of the `pendingChange` table: one queued change per task, in queue order (`sequence`).
/// The payload columns are `nil` for a delete.
struct PendingChangeRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "pendingChange"

    enum Columns {
        static let sequence = Column(CodingKeys.sequence)
        static let scope = Column(CodingKeys.scope)
        static let taskID = Column(CodingKeys.taskID)
    }

    var sequence: Int64?
    var scope: String
    var taskID: String
    var kind: PendingChange.Kind
    var isLocal: Bool
    var revision: Int
    var title: String?
    var notes: String?
    var priority: String?
    var isComplete: Bool?
    var dueDate: Date?

    init(scope: String, taskID: UUID, kind: PendingChange.Kind, isLocal: Bool, task: TaskItem?) {
        self.scope = scope
        self.taskID = taskID.uuidString
        self.kind = kind
        self.isLocal = isLocal
        self.revision = 0
        setPayload(task)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        sequence = inserted.rowID
    }

    mutating func setPayload(_ task: TaskItem?) {
        title = task?.title
        notes = task?.notes
        priority = task?.priority.rawValue
        isComplete = task?.isComplete
        dueDate = task?.dueDate
    }

    /// `nil` for a row this app version can't read.
    var change: PendingChange? {
        guard let id = UUID(uuidString: taskID) else { return nil }
        return PendingChange(taskID: id, kind: kind, isLocal: isLocal, revision: revision, task: task(id: id))
    }

    /// The values to send; `nil` for a delete or a payload this version can't read.
    private func task(id: UUID) -> TaskItem? {
        guard let title, let notes, let isComplete,
              let priority = priority.flatMap(TaskPriority.init(rawValue:)) else { return nil }
        return TaskItem(
            id: id,
            title: title,
            notes: notes,
            priority: priority,
            isComplete: isComplete,
            dueDate: dueDate,
            isPendingSync: true
        )
    }

    static func all(in scope: String) -> QueryInterfaceRequest<Self> {
        filter(Columns.scope == scope).order(Columns.sequence)
    }

    static func find(_ id: UUID, in scope: String, _ db: Database) throws -> Self? {
        try filter(Columns.scope == scope && Columns.taskID == id.uuidString).fetchOne(db)
    }

    /// Merges into the task's queued change, so the queue holds at most one change per task:
    /// - create or update, then update → the same kind with the newer values;
    /// - create or update, then delete → delete (a never-synced create is then dropped by the sync
    ///   without a request);
    /// - anything after a delete is ignored.
    static func enqueue(_ change: LocalChange, in scope: String, _ db: Database) throws {
        switch change {
        case .create(let task):
            var record = Self(scope: scope, taskID: task.id, kind: .create, isLocal: true, task: task)
            try record.insert(db)
        case .update(let task):
            let id = try TaskAlias.resolve(task.id, in: scope, db)
            guard var existing = try find(id, in: scope, db) else {
                var record = Self(scope: scope, taskID: id, kind: .update, isLocal: false, task: task)
                try record.insert(db)
                return
            }
            switch existing.kind {
            case .create, .update:
                existing.setPayload(task)
                existing.revision += 1
                try existing.update(db)
            case .delete:
                return
            }
        case .delete(let rawID):
            let id = try TaskAlias.resolve(rawID, in: scope, db)
            guard var existing = try find(id, in: scope, db) else {
                var record = Self(scope: scope, taskID: id, kind: .delete, isLocal: false, task: nil)
                try record.insert(db)
                return
            }
            switch existing.kind {
            case .create, .update:
                existing.kind = .delete
                existing.setPayload(nil)
                existing.revision += 1
                try existing.update(db)
            case .delete:
                return
            }
        }
    }

    static func settle(_ change: PendingChange, _ outcome: SyncOutcome, in scope: String, _ db: Database) throws {
        let current = try find(change.taskID, in: scope, db)
        let isUnchanged = current?.revision == change.revision
        switch outcome {
        case .created(let created), .createdNeedingUpdate(let created):
            try TaskAlias(scope: scope, localID: change.taskID.uuidString, serverID: created.id.uuidString).save(db)
            try TaskRecord.upsert(created, in: scope, db)
            guard var current else { return }
            let needsUpdate = switch outcome {
            case .createdNeedingUpdate: true
            case .created, .updated, .deleted, .rejected: false
            }
            if isUnchanged, !needsUpdate {
                try current.delete(db)
            } else {
                // Edited while the create was in flight, or not fully applied by it: send the
                // local values to the server's task.
                current.taskID = created.id.uuidString
                current.isLocal = false
                switch current.kind {
                case .create: current.kind = .update
                case .update, .delete: break
                }
                try current.update(db)
            }
        case .updated(let updated):
            try TaskRecord.upsert(updated, in: scope, db)
            if isUnchanged { try current?.delete(db) }
        case .deleted:
            try TaskRecord.deleteOne(db, key: ["scope": scope, "id": change.taskID.uuidString])
            try current?.delete(db)
        case .rejected:
            if isUnchanged { try current?.delete(db) }
        }
    }
}

/// Row of the `taskAlias` table: a task created offline (`localID`) and the id the server gave it.
/// Screens keep using the local id until the next fetch, so later calls are mapped through this.
struct TaskAlias: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "taskAlias"

    var scope: String
    var localID: String
    var serverID: String

    static func resolve(_ id: UUID, in scope: String, _ db: Database) throws -> UUID {
        let alias = try fetchOne(db, key: ["scope": scope, "localID": id.uuidString])
        return alias.flatMap { UUID(uuidString: $0.serverID) } ?? id
    }
}

/// A FIFO async mutex: `lock()` suspends until every earlier holder has called `unlock()`.
actor AsyncLock {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        guard isLocked else {
            isLocked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func unlock() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
