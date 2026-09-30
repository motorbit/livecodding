import Foundation
import L10n
import TaskClient

public struct TaskDetailViewState: Equatable {
    public var task: TaskItem
    public var title: String
    public var notes: String
    public var priority: TaskPriority
    public var selectedPriorityLabel: String
    public var hasDueDate: Bool
    /// Canonical due day (00:00 UTC); set while `hasDueDate` is on.
    public var dueDate: Date?
    public var dueDateToggleLabel: String
    public var dueDateLabel: String
    public var navigationTitle: String
    public var titleFieldLabel: String
    public var notesFieldLabel: String
    public var priorityFieldLabel: String
    public var lowPriorityLabel: String
    public var mediumPriorityLabel: String
    public var highPriorityLabel: String
    public var saveButtonTitle: String
    public var deleteButtonTitle: String
    public var retryButtonTitle: String
    public var deleteConfirmationTitle: String
    public var deleteConfirmationMessage: String
    public var cancelButtonTitle: String
    public var confirmDeleteButtonTitle: String
    public var inlineErrorMessage: String?
    public var titleValidationMessage: String?
    public var isDirty: Bool
    public var isSaving: Bool
    public var isDeleting: Bool
    public var canEditFields: Bool
    public var canSave: Bool
    public var canDelete: Bool
    public var canRetry: Bool
    public var isDeleteConfirmationPresented: Bool

    public init(task: TaskItem) {
        self.task = task
        title = task.title
        notes = task.notes
        priority = task.priority
        hasDueDate = task.dueDate != nil
        dueDate = task.dueDate
        dueDateToggleLabel = L10n.TaskDetail.dueDateToggle
        dueDateLabel = L10n.TaskDetail.dueDateLabel
        switch task.priority {
        case .low:
            selectedPriorityLabel = L10n.TaskDetail.lowPriority
        case .medium:
            selectedPriorityLabel = L10n.TaskDetail.mediumPriority
        case .high:
            selectedPriorityLabel = L10n.TaskDetail.highPriority
        }
        navigationTitle = L10n.TaskDetail.title
        titleFieldLabel = L10n.TaskDetail.titleField
        notesFieldLabel = L10n.TaskDetail.notesField
        priorityFieldLabel = L10n.TaskDetail.priorityField
        lowPriorityLabel = L10n.TaskDetail.lowPriority
        mediumPriorityLabel = L10n.TaskDetail.mediumPriority
        highPriorityLabel = L10n.TaskDetail.highPriority
        saveButtonTitle = L10n.TaskDetail.save
        deleteButtonTitle = L10n.TaskDetail.delete
        retryButtonTitle = L10n.TaskDetail.retry
        deleteConfirmationTitle = L10n.TaskDetail.deleteConfirmationTitle
        deleteConfirmationMessage = L10n.TaskDetail.deleteConfirmationMessage
        cancelButtonTitle = L10n.TaskDetail.cancel
        confirmDeleteButtonTitle = L10n.TaskDetail.confirmDelete
        inlineErrorMessage = nil
        titleValidationMessage = nil
        isDirty = false
        isSaving = false
        isDeleting = false
        canEditFields = true
        canSave = false
        canDelete = true
        canRetry = false
        isDeleteConfirmationPresented = false
    }
}
