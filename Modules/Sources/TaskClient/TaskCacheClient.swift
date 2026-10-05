import Dependencies
import DependenciesMacros
import Foundation
import GRDB

/// On-disk cache boundary of `TaskClient`: the last known task list, so the board can show tasks
/// before the network answers. Cleared on every environment switch. Rows are tagged with a `scope`
/// (the environment name) and read by it, so a write that lands after the switch can't show up in
/// the new environment. SQLite through GRDB; only Sendable domain values cross this boundary.
@DependencyClient
struct TaskCacheClient: Sendable {
    /// Cached tasks in list order; empty until `replaceAll` has stored a full list for `scope`.
    var tasks: @Sendable (_ scope: String) async throws -> [TaskItem]
    /// Replaces everything cached for `scope` with a freshly fetched list.
    var replaceAll: @Sendable (_ scope: String, _ tasks: [TaskItem]) async throws -> Void
    /// Inserts a task at the end of the list, or updates it in place. Ignored while `scope` has no
    /// full list, so a partial list is never mistaken for the saved one.
    var upsert: @Sendable (_ scope: String, _ task: TaskItem) async throws -> Void
    var delete: @Sendable (_ scope: String, _ id: UUID) async throws -> Void
    /// Removes everything, in every scope.
    var clear: @Sendable () async throws -> Void
}

extension TaskCacheClient: DependencyKey {
    static let liveValue = TaskCacheClient.live(database: TaskCacheDatabase(location: .file(.taskCache)))
    static var previewValue: TaskCacheClient { .inMemory() }
    static let testValue = TaskCacheClient()
}

extension DependencyValues {
    var taskCacheClient: TaskCacheClient {
        get { self[TaskCacheClient.self] }
        set { self[TaskCacheClient.self] = newValue }
    }
}

extension TaskCacheClient {
    /// A private in-memory database; for previews and tests.
    static func inMemory() -> Self {
        .live(database: TaskCacheDatabase(location: .inMemory))
    }

    static func live(database: TaskCacheDatabase) -> Self {
        Self(
            tasks: { scope in
                try await database.queue().read { db in
                    guard try CachedScope.exists(db, key: scope) else { return [] }
                    return try TaskRecord
                        .filter(TaskRecord.Columns.scope == scope)
                        .order(TaskRecord.Columns.position)
                        .fetchAll(db)
                        .compactMap(\.item)
                }
            },
            replaceAll: { scope, tasks in
                try await database.queue().write { db in
                    try TaskRecord.filter(TaskRecord.Columns.scope == scope).deleteAll(db)
                    try CachedScope(scope: scope).save(db)
                    for (position, task) in tasks.enumerated() {
                        try TaskRecord(scope: scope, position: position, item: task).insert(db)
                    }
                }
            },
            upsert: { scope, task in
                try await database.queue().write { db in
                    guard try CachedScope.exists(db, key: scope) else { return }
                    let existing = try TaskRecord.fetchOne(db, key: ["scope": scope, "id": task.id.uuidString])
                    let position = try existing?.position ?? TaskRecord.nextPosition(in: scope, db)
                    try TaskRecord(scope: scope, position: position, item: task).save(db)
                }
            },
            delete: { scope, id in
                _ = try await database.queue().write { db in
                    try TaskRecord.deleteOne(db, key: ["scope": scope, "id": id.uuidString])
                }
            },
            clear: {
                _ = try await database.queue().write { db in
                    try TaskRecord.deleteAll(db)
                    try CachedScope.deleteAll(db)
                }
            }
        )
    }
}

/// Opens the database lazily, off the caller's actor, and runs the migrations once.
final class TaskCacheDatabase: Sendable {
    enum Location: Sendable {
        case file(URL)
        case inMemory
    }

    private let location: Location
    private let opened = LockIsolated<DatabaseQueue?>(nil)

    init(location: Location) {
        self.location = location
    }

    @concurrent
    func queue() async throws -> DatabaseQueue {
        try opened.withValue { opened in
            if let opened { return opened }
            let queue = try open()
            try Self.migrator.migrate(queue)
            opened = queue
            return queue
        }
    }

    private func open() throws -> DatabaseQueue {
        switch location {
        case .file(let url):
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            return try DatabaseQueue(path: url.path(percentEncoded: false))
        case .inMemory:
            return try DatabaseQueue()
        }
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-create-task") { db in
            try db.create(table: TaskRecord.databaseTableName) { table in
                table.column("scope", .text).notNull()
                table.column("id", .text).notNull()
                table.column("position", .integer).notNull()
                table.column("title", .text).notNull()
                table.column("notes", .text).notNull()
                table.column("priority", .text).notNull()
                table.column("isComplete", .boolean).notNull()
                table.column("dueDate", .datetime)
                table.primaryKey(["scope", "id"])
            }
            try db.create(table: CachedScope.databaseTableName) { table in
                table.primaryKey("scope", .text)
            }
        }
        return migrator
    }
}

extension URL {
    /// In Caches: rebuildable from the server, so not backed up and purgeable by the system.
    static var taskCache: URL {
        .cachesDirectory.appending(path: "TaskCache.sqlite")
    }
}

/// A scope whose full list has been stored by `replaceAll`.
struct CachedScope: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cachedScope"
    var scope: String
}

/// Row of the `task` table. Stores enums and ids as text so the schema doesn't depend on Swift
/// encodings.
struct TaskRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "task"

    enum Columns {
        static let scope = Column(CodingKeys.scope)
        static let position = Column(CodingKeys.position)
    }

    var scope: String
    var id: String
    var position: Int
    var title: String
    var notes: String
    var priority: String
    var isComplete: Bool
    var dueDate: Date?

    init(scope: String, position: Int, item: TaskItem) {
        self.scope = scope
        self.id = item.id.uuidString
        self.position = position
        self.title = item.title
        self.notes = item.notes
        self.priority = item.priority.rawValue
        self.isComplete = item.isComplete
        self.dueDate = item.dueDate
    }

    /// `nil` for a row this app version can't read (e.g. an unknown priority).
    var item: TaskItem? {
        guard let id = UUID(uuidString: id), let priority = TaskPriority(rawValue: priority) else {
            return nil
        }
        return TaskItem(
            id: id,
            title: title,
            notes: notes,
            priority: priority,
            isComplete: isComplete,
            dueDate: dueDate
        )
    }

    static func nextPosition(in scope: String, _ db: Database) throws -> Int {
        let last = try Int.fetchOne(
            db,
            sql: "SELECT MAX(position) FROM \(databaseTableName) WHERE scope = ?",
            arguments: [scope]
        )
        return last.map { $0 + 1 } ?? 0
    }
}
