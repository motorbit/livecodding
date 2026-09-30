import TaskClient

public enum TaskDetailViewEvent {
    case titleChanged(String)
    case notesChanged(String)
    case priorityChanged(TaskPriority)
    case saveTapped
    case deleteTapped
    case deleteConfirmed
    case deleteCancelled
    case retryTapped
}
