import Combine
import Dependencies
import Foundation
import L10n
import TaskClient

public final class AddTaskViewModel: ObservableObject {
    @Published public private(set) var state: AddTaskViewState
    public var onEvent: ((AddTaskViewModelEvent) -> Void)?

    @Dependency(\.taskClient) private var taskClient
    @Dependency(\.date) private var date
    @Dependency(\.calendar) private var calendar

    var saveTask: Task<Void, Never>?
    private var saveGeneration = 0

    public init(state: AddTaskViewState = AddTaskViewState()) {
        self.state = state
    }

    deinit {
        saveTask?.cancel()
    }

    public func trigger(_ event: AddTaskViewEvent) {
        switch event {
        case .titleChanged(let title):
            state.taskTitle = title
            clearError()
        case .notesChanged(let notes):
            state.notes = notes
            clearError()
        case .priorityChanged(let priority):
            state.priority = priority
            clearError()
        case .dueDateToggled(let isOn):
            guard isOn != state.hasDueDate else { return }
            state.hasDueDate = isOn
            state.dueDate = isOn ? DueDay.day(containing: date.now, in: calendar) : nil
            clearError()
        case .dueDateChanged(let dueDate):
            guard state.hasDueDate else { return }
            state.dueDate = DueDay.normalized(dueDate)
            clearError()
        case .saveTapped, .retryTapped:
            save()
        case .cancelTapped:
            guard !state.isSaving else { return }
            onEvent?(.closeRequested)
        }
    }

    private enum InternalAction {
        case created(TaskItem)
        case failed
    }

    private func handle(_ action: InternalAction) {
        state.isSaving = false

        switch action {
        case .created(let task):
            state.errorMessage = nil
            state.canRetry = false
            onEvent?(.created(task))
        case .failed:
            state.errorMessage = L10n.AddTask.saveError
            state.canRetry = true
        }
    }

    private func save() {
        guard !state.isSaving else { return }
        let title = state.taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            state.errorMessage = L10n.AddTask.titleRequired
            state.canRetry = false
            return
        }

        let draft = TaskDraft(title: title, notes: state.notes, priority: state.priority, dueDate: state.dueDate)
        let taskClient = taskClient
        saveTask?.cancel()
        saveGeneration += 1
        let generation = saveGeneration
        state.isSaving = true
        state.errorMessage = nil
        state.canRetry = false

        saveTask = Task { [weak self] in
            do {
                let task = try await taskClient.createTask(draft)
                guard !Task.isCancelled, let self, self.saveGeneration == generation else { return }
                self.handle(.created(task))
            } catch {
                guard !Task.isCancelled, let self, self.saveGeneration == generation else { return }
                self.handle(.failed)
            }
        }
    }

    private func clearError() {
        state.errorMessage = nil
        state.canRetry = false
    }
}
