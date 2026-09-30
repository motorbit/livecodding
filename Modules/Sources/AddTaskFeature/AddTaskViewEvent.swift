import TaskClient

public enum AddTaskViewEvent {
    case titleChanged(String)
    case notesChanged(String)
    case priorityChanged(TaskPriority)
    case saveTapped
    case retryTapped
    case cancelTapped
}
