import Foundation
import TaskClient

public enum TaskDetailViewModelEvent: Equatable {
    case dirtyChanged(Bool)
    case updated(TaskItem)
    case deleted(UUID)
}
