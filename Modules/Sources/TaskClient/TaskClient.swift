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

    public init(
        id: UUID,
        title: String,
        notes: String = "",
        priority: TaskPriority,
        isComplete: Bool = false
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.priority = priority
        self.isComplete = isComplete
    }
}

public struct TaskDraft: Equatable, Sendable {
    public var title: String
    public var notes: String
    public var priority: TaskPriority

    public init(title: String, notes: String = "", priority: TaskPriority = .medium) {
        self.title = title
        self.notes = notes
        self.priority = priority
    }
}

public enum TaskClientError: Error, Equatable, Sendable {
    case unavailable
    case simulatedFailure
}

@DependencyClient
public struct TaskClient: Sendable {
    public var fetchTasks: @Sendable () async throws -> [TaskItem]
    public var createTask: @Sendable (_ draft: TaskDraft) async throws -> TaskItem
    public var updateTask: @Sendable (_ task: TaskItem) async throws -> TaskItem
    public var deleteTask: @Sendable (_ id: UUID) async throws -> Void
}

extension TaskClient: DependencyKey {
    public static let liveValue = TaskClient(
        fetchTasks: {
            reportIssue("TaskClient live implementation is not configured")
            throw TaskClientError.unavailable
        },
        createTask: { _ in
            reportIssue("TaskClient live implementation is not configured")
            throw TaskClientError.unavailable
        },
        updateTask: { _ in
            reportIssue("TaskClient live implementation is not configured")
            throw TaskClientError.unavailable
        },
        deleteTask: { _ in
            reportIssue("TaskClient live implementation is not configured")
            throw TaskClientError.unavailable
        }
    )

    public static let previewValue = TaskClient(
        fetchTasks: { TaskItem.samples },
        createTask: { draft in
            TaskItem(
                id: UUID(),
                title: draft.title,
                notes: draft.notes,
                priority: draft.priority
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
