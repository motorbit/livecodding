import Foundation
import L10n
import TaskClient

public struct AddTaskViewState: Equatable {
    public var title: String
    public var taskTitle: String
    public var titleLabel: String
    public var titlePlaceholder: String
    public var notes: String
    public var notesLabel: String
    public var notesPlaceholder: String
    public var priority: TaskPriority
    public var priorityLabel: String
    public var lowPriorityLabel: String
    public var mediumPriorityLabel: String
    public var highPriorityLabel: String
    public var hasDueDate: Bool
    /// Canonical due day (00:00 UTC); set while `hasDueDate` is on.
    public var dueDate: Date?
    public var dueDateToggleLabel: String
    public var dueDateLabel: String
    public var saveLabel: String
    public var cancelLabel: String
    public var retryLabel: String
    public var errorMessage: String?
    public var canRetry: Bool
    public var isSaving: Bool

    public init(
        title: String = L10n.AddTask.title,
        taskTitle: String = "",
        titleLabel: String = L10n.AddTask.titleLabel,
        titlePlaceholder: String = L10n.AddTask.titlePlaceholder,
        notes: String = "",
        notesLabel: String = L10n.AddTask.notesLabel,
        notesPlaceholder: String = L10n.AddTask.notesPlaceholder,
        priority: TaskPriority = .medium,
        priorityLabel: String = L10n.AddTask.priorityLabel,
        lowPriorityLabel: String = L10n.AddTask.lowPriority,
        mediumPriorityLabel: String = L10n.AddTask.mediumPriority,
        highPriorityLabel: String = L10n.AddTask.highPriority,
        hasDueDate: Bool = false,
        dueDate: Date? = nil,
        dueDateToggleLabel: String = L10n.AddTask.dueDateToggle,
        dueDateLabel: String = L10n.AddTask.dueDateLabel,
        saveLabel: String = L10n.AddTask.save,
        cancelLabel: String = L10n.AddTask.cancel,
        retryLabel: String = L10n.AddTask.retry,
        errorMessage: String? = nil,
        canRetry: Bool = false,
        isSaving: Bool = false
    ) {
        self.title = title
        self.taskTitle = taskTitle
        self.titleLabel = titleLabel
        self.titlePlaceholder = titlePlaceholder
        self.notes = notes
        self.notesLabel = notesLabel
        self.notesPlaceholder = notesPlaceholder
        self.priority = priority
        self.priorityLabel = priorityLabel
        self.lowPriorityLabel = lowPriorityLabel
        self.mediumPriorityLabel = mediumPriorityLabel
        self.highPriorityLabel = highPriorityLabel
        self.hasDueDate = hasDueDate
        self.dueDate = dueDate
        self.dueDateToggleLabel = dueDateToggleLabel
        self.dueDateLabel = dueDateLabel
        self.saveLabel = saveLabel
        self.cancelLabel = cancelLabel
        self.retryLabel = retryLabel
        self.errorMessage = errorMessage
        self.canRetry = canRetry
        self.isSaving = isSaving
    }
}
