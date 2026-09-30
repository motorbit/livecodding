import Foundation
import TaskClient

public enum AddTaskViewEvent {
    case titleChanged(String)
    case notesChanged(String)
    case priorityChanged(TaskPriority)
    case dueDateToggled(Bool)
    /// A date from the UTC-zoned picker (`DueDay.timeZone`).
    case dueDateChanged(Date)
    case saveTapped
    case retryTapped
    case cancelTapped
}
