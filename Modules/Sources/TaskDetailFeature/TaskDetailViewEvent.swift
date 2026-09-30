import Foundation
import TaskClient

public enum TaskDetailViewEvent {
    case titleChanged(String)
    case notesChanged(String)
    case priorityChanged(TaskPriority)
    case dueDateToggled(Bool)
    /// A date from the UTC-zoned picker (`DueDay.timeZone`).
    case dueDateChanged(Date)
    case saveTapped
    case deleteTapped
    case deleteConfirmed
    case deleteCancelled
    case retryTapped
}
