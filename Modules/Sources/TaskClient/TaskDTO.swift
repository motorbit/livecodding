import Foundation

/// Wire format of the mock Task API (`/tasks`). Matches the challenge JSON shape plus `id` and
/// `due_date` (`yyyy-MM-dd`).
struct TaskDTO: Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var notes: String
    var priority: PriorityDTO
    var done: Bool
    var dueDate: String?

    enum CodingKeys: String, CodingKey {
        case id, title, notes, priority, done
        case dueDate = "due_date"
    }
}

/// Request body for `POST /tasks`.
struct TaskDraftDTO: Codable, Equatable, Sendable {
    var title: String
    var notes: String
    var priority: PriorityDTO
    var dueDate: String?

    enum CodingKeys: String, CodingKey {
        case title, notes, priority
        case dueDate = "due_date"
    }
}

enum PriorityDTO: String, Codable, Equatable, Sendable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

// MARK: - Mapping

extension TaskDTO {
    init(_ item: TaskItem) {
        self.init(
            id: item.id,
            title: item.title,
            notes: item.notes,
            priority: PriorityDTO(item.priority),
            done: item.isComplete,
            dueDate: item.dueDate.map(DueDateFormat.string(from:))
        )
    }

    func toDomain() throws(TaskClientError) -> TaskItem {
        TaskItem(
            id: id,
            title: title,
            notes: notes,
            priority: priority.domain,
            isComplete: done,
            dueDate: try dueDate.map(DueDateFormat.date(from:))
        )
    }
}

extension TaskDraftDTO {
    init(_ draft: TaskDraft) {
        self.init(
            title: draft.title,
            notes: draft.notes,
            priority: PriorityDTO(draft.priority),
            dueDate: draft.dueDate.map(DueDateFormat.string(from:))
        )
    }
}

extension PriorityDTO {
    init(_ priority: TaskPriority) {
        switch priority {
        case .low: self = .low
        case .medium: self = .medium
        case .high: self = .high
        }
    }

    var domain: TaskPriority {
        switch self {
        case .low: .low
        case .medium: .medium
        case .high: .high
        }
    }
}

/// `yyyy-MM-dd` in UTC, so a calendar day never shifts with the device time zone.
enum DueDateFormat {
    private static let style = Date.ISO8601FormatStyle(timeZone: .gmt)
        .year()
        .month()
        .day()
        .dateSeparator(.dash)

    static func string(from date: Date) -> String {
        date.formatted(style)
    }

    static func date(from string: String) throws(TaskClientError) -> Date {
        do {
            return try style.parse(string)
        } catch {
            throw .unavailable
        }
    }
}
