import Dependencies
import DependenciesMacros
import Foundation

public enum TaskPriority: String, Codable, CaseIterable, Equatable, Sendable {
    case low
    case medium
    case high
}

public struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var notes: String
    public var priority: TaskPriority
    public var isComplete: Bool
    /// A calendar day, stored as 00:00 UTC of that day. Transferred as `yyyy-MM-dd`.
    public var dueDate: Date?

    public init(
        id: UUID,
        title: String,
        notes: String = "",
        priority: TaskPriority,
        isComplete: Bool = false,
        dueDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.priority = priority
        self.isComplete = isComplete
        self.dueDate = dueDate
    }
}

public struct TaskDraft: Equatable, Sendable {
    public var title: String
    public var notes: String
    public var priority: TaskPriority
    /// Same convention as `TaskItem.dueDate`.
    public var dueDate: Date?

    public init(
        title: String,
        notes: String = "",
        priority: TaskPriority = .medium,
        dueDate: Date? = nil
    ) {
        self.title = title
        self.notes = notes
        self.priority = priority
        self.dueDate = dueDate
    }
}

public enum TaskClientError: Error, Equatable, Sendable {
    /// The request was rejected, e.g. a blank title (HTTP 400).
    case validation
    /// The task doesn't exist (HTTP 404).
    case notFound
    /// The service failed or returned an unreadable response (HTTP 5xx, transport, decoding).
    case unavailable
}

@DependencyClient
public struct TaskClient: Sendable {
    public var fetchTasks: @Sendable () async throws -> [TaskItem]
    public var createTask: @Sendable (_ draft: TaskDraft) async throws -> TaskItem
    public var updateTask: @Sendable (_ task: TaskItem) async throws -> TaskItem
    public var deleteTask: @Sendable (_ id: UUID) async throws -> Void
}

extension TaskClient: DependencyKey {
    public static let liveValue = TaskClient.live()

    public static let previewValue = TaskClient(
        fetchTasks: { TaskItem.samples },
        createTask: { draft in
            TaskItem(
                id: UUID(),
                title: draft.title,
                notes: draft.notes,
                priority: draft.priority,
                dueDate: draft.dueDate
            )
        },
        updateTask: { $0 },
        deleteTask: { _ in }
    )

    public static let testValue = TaskClient()
}

public extension DependencyValues {
    var taskClient: TaskClient {
        get { self[TaskClient.self] }
        set { self[TaskClient.self] = newValue }
    }
}

public extension TaskItem {
    static let samples = [
        TaskItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Renew domain registration",
            notes: "Expires end of month",
            priority: .high
        ),
        TaskItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            title: "Reply to design feedback",
            priority: .medium
        ),
        TaskItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            title: "Book dentist",
            priority: .low,
            isComplete: true
        ),
        TaskItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            title: "Migrate the analytics pipeline to the new warehouse and validate dashboards",
            notes: "Long one — check layout",
            priority: .medium
        ),
    ]
}
