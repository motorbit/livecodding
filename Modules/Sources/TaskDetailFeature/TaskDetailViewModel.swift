import Combine
import Dependencies
import Foundation
import L10n
import TaskClient

public final class TaskDetailViewModel: ObservableObject {
    @Published public private(set) var state: TaskDetailViewState
    public var onEvent: ((TaskDetailViewModelEvent) -> Void)?

    @Dependency(\.taskClient) private var taskClient

    var writeTask: Task<Void, Never>?
    private var writeGeneration = 0
    private var retryOperation: RetryOperation?

    private enum RetryOperation {
        case save
        case delete
    }

    public init(state: TaskDetailViewState) {
        self.state = state
    }

    deinit {
        writeTask?.cancel()
    }

    public func trigger(_ event: TaskDetailViewEvent) {
        switch event {
        case .titleChanged(let title):
            state.title = title
            clearTransientMessages()
            updateDirtyState()
        case .notesChanged(let notes):
            state.notes = notes
            clearTransientMessages()
            updateDirtyState()
        case .priorityChanged(let priority):
            state.priority = priority
            state.selectedPriorityLabel = priorityLabel(for: priority)
            clearTransientMessages()
            updateDirtyState()
        case .saveTapped:
            save()
        case .deleteTapped:
            guard state.canDelete else { return }
            state.inlineErrorMessage = nil
            state.titleValidationMessage = nil
            retryOperation = nil
            state.canRetry = false
            state.isDeleteConfirmationPresented = true
        case .deleteConfirmed:
            guard state.isDeleteConfirmationPresented else { return }
            state.isDeleteConfirmationPresented = false
            delete()
        case .deleteCancelled:
            state.isDeleteConfirmationPresented = false
        case .retryTapped:
            switch retryOperation {
            case .save:
                save()
            case .delete:
                delete()
            case nil:
                break
            }
        }
    }

    private enum InternalAction {
        case saveSucceeded(TaskItem)
        case saveFailed
        case deleteSucceeded(UUID)
        case deleteFailed
    }

    private func handle(_ action: InternalAction) {
        switch action {
        case .saveSucceeded(let task):
            state.task = task
            state.title = task.title
            state.notes = task.notes
            state.priority = task.priority
            state.isSaving = false
            state.inlineErrorMessage = nil
            state.titleValidationMessage = nil
            retryOperation = nil
            updateCapabilities()
            updateDirtyState()
            onEvent?(.updated(task))
        case .saveFailed:
            state.isSaving = false
            state.inlineErrorMessage = L10n.TaskDetail.saveError
            retryOperation = .save
            updateCapabilities()
        case .deleteSucceeded(let id):
            state.isDeleting = false
            state.inlineErrorMessage = nil
            retryOperation = nil
            updateCapabilities()
            onEvent?(.deleted(id))
        case .deleteFailed:
            state.isDeleting = false
            state.isDeleteConfirmationPresented = false
            state.inlineErrorMessage = L10n.TaskDetail.deleteError
            retryOperation = .delete
            updateCapabilities()
        }
    }

    private func save() {
        guard !state.isSaving, !state.isDeleting, state.isDirty else { return }
        let normalizedTitle = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            state.titleValidationMessage = L10n.TaskDetail.titleRequired
            return
        }

        writeTask?.cancel()
        writeGeneration += 1
        let generation = writeGeneration
        let client = taskClient
        let task = TaskItem(
            id: state.task.id,
            title: normalizedTitle,
            notes: state.notes,
            priority: state.priority,
            isComplete: state.task.isComplete,
            dueDate: state.task.dueDate
        )
        state.isSaving = true
        state.inlineErrorMessage = nil
        state.titleValidationMessage = nil
        retryOperation = nil
        updateCapabilities()

        writeTask = Task { [weak self] in
            let action: InternalAction
            do {
                action = .saveSucceeded(try await client.updateTask(task))
            } catch {
                action = .saveFailed
            }
            guard !Task.isCancelled, let self, self.writeGeneration == generation else { return }
            self.handle(action)
        }
    }

    private func delete() {
        guard !state.isSaving, !state.isDeleting else { return }
        writeTask?.cancel()
        writeGeneration += 1
        let generation = writeGeneration
        let client = taskClient
        let id = state.task.id
        state.isDeleting = true
        state.inlineErrorMessage = nil
        retryOperation = nil
        updateCapabilities()

        writeTask = Task { [weak self] in
            let action: InternalAction
            do {
                try await client.deleteTask(id: id)
                action = .deleteSucceeded(id)
            } catch {
                action = .deleteFailed
            }
            guard !Task.isCancelled, let self, self.writeGeneration == generation else { return }
            self.handle(action)
        }
    }

    private func clearTransientMessages() {
        state.inlineErrorMessage = nil
        state.titleValidationMessage = nil
        retryOperation = nil
        state.canRetry = false
    }

    private func updateDirtyState() {
        let draft = TaskDraft(title: state.title, notes: state.notes, priority: state.priority)
        let confirmedDraft = TaskDraft(
            title: state.task.title,
            notes: state.task.notes,
            priority: state.task.priority
        )
        let isDirty = draft != confirmedDraft
        guard state.isDirty != isDirty else {
            updateCapabilities()
            return
        }
        state.isDirty = isDirty
        updateCapabilities()
        onEvent?(.dirtyChanged(isDirty))
    }

    private func updateCapabilities() {
        let isWorking = state.isSaving || state.isDeleting
        state.canEditFields = !isWorking
        state.canSave = state.isDirty && !isWorking
        state.canDelete = !isWorking
        state.canRetry = retryOperation != nil && !isWorking
    }

    private func priorityLabel(for priority: TaskPriority) -> String {
        switch priority {
        case .low:
            L10n.TaskDetail.lowPriority
        case .medium:
            L10n.TaskDetail.mediumPriority
        case .high:
            L10n.TaskDetail.highPriority
        }
    }
}
