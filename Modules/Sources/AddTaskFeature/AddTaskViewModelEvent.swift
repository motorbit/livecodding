import TaskClient

public enum AddTaskViewModelEvent: Equatable {
    case created(TaskItem)
    case closeRequested
}
