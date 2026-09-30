import AddTaskFeature
import Combine
import Dependencies
import Foundation
import L10n
import TaskClient
import TaskDetailFeature

public final class TaskBoardViewModel: ObservableObject {
    @Published public private(set) var state: TaskBoardViewState
    public private(set) var addViewModel: AddTaskViewModel?
    public private(set) var detailViewModel: TaskDetailViewModel?

    @Dependency(\.taskClient) private var taskClient

    var loadTask: Task<Void, Never>?
    var completionTasks: [UUID: Task<Void, Never>] = [:]
    private var loadGeneration = 0
    private var completionGeneration = 0
    private var mutationGeneration = 0
    private var tasks: [TaskItem] = []
    private var completionStatus: [UUID: CompletionStatus] = [:]

    private enum CompletionStatus: Equatable {
        case inFlight(generation: Int)
        case failed
    }

    public init(state: TaskBoardViewState = TaskBoardViewState()) {
        self.state = state
    }

    deinit {
        loadTask?.cancel()
        completionTasks.values.forEach { $0.cancel() }
    }

    /// Pull-to-refresh entry point for `.refreshable`, a scoped exception to the sync-`trigger`
    /// contract (ADR 0003). It reloads, then suspends until the latest load has been handled,
    /// including a load restarted by a concurrent mutation or a Retry.
    public func refresh() async {
        trigger(.refreshRequested)
        var awaited: Task<Void, Never>?
        while let current = loadTask, current != awaited {
            awaited = current
            await current.value
        }
    }

    public func trigger(_ event: TaskBoardViewEvent) {
        switch event {
        case .onAppear:
            guard loadGeneration == 0 else { return }
            load()
        case .retryTapped, .refreshRequested:
            load()
        case .addTapped:
            guard addViewModel == nil else { return }
            let child = withDependencies(from: self) { AddTaskViewModel() }
            child.onEvent = { [weak self] in self?.handle($0) }
            objectWillChange.send()
            addViewModel = child
        case .addDismissed:
            dismissAdd()
        case .taskTapped(let id):
            openDetail(id: id)
        case .completionToggled(let id), .completionRetryTapped(let id):
            toggleCompletion(id: id)
        case .navigationPathChanged(let path):
            guard path != state.navigationPath else { return }
            if path.isEmpty, detailViewModel != nil, state.isDetailDirty {
                // Keep the pushed route until the user explicitly discards.
                state.isDiscardConfirmationPresented = true
                return
            }
            state.navigationPath = path
            if path.isEmpty { clearDetail() }
        case .detailBackTapped:
            if state.isDetailDirty {
                state.isDiscardConfirmationPresented = true
            } else {
                popDetail()
            }
        case .discardConfirmed:
            guard state.isDiscardConfirmationPresented else { return }
            popDetail()
        case .discardCancelled:
            state.isDiscardConfirmationPresented = false
        }
    }

    // MARK: - Effects

    private enum InternalAction {
        case loaded([TaskItem])
        case loadFailed
        case completionSucceeded(TaskItem)
        case completionFailed(UUID)
    }

    private func handle(_ action: InternalAction) {
        switch action {
        case .loaded(let items):
            tasks = items
            let ids = Set(items.map(\.id))
            completionStatus = completionStatus.filter { ids.contains($0.key) }
            state.reloadErrorMessage = nil
            state.phase = items.isEmpty ? .empty : .content
            rebuildRows()
        case .loadFailed:
            switch state.phase {
            case .content, .empty:
                state.reloadErrorMessage = L10n.TaskBoard.reloadError
            case .loading, .failed:
                state.phase = .failed
            }
        case .completionSucceeded(let item):
            mutationGeneration += 1
            completionStatus[item.id] = nil
            completionTasks[item.id] = nil
            if let index = tasks.firstIndex(where: { $0.id == item.id }) {
                tasks[index] = item
            }
            rebuildRows()
        case .completionFailed(let id):
            completionStatus[id] = .failed
            completionTasks[id] = nil
            rebuildRows()
        }
    }

    private func load() {
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let currentMutationGeneration = mutationGeneration
        let client = taskClient
        switch state.phase {
        case .loading, .failed:
            state.phase = .loading
        case .content, .empty:
            break
        }
        state.reloadErrorMessage = nil

        loadTask = Task { [weak self] in
            let action: InternalAction
            do {
                action = .loaded(try await client.fetchTasks())
            } catch {
                action = .loadFailed
            }
            guard !Task.isCancelled, let self, self.loadGeneration == generation else { return }
            guard self.mutationGeneration == currentMutationGeneration else {
                self.load()
                return
            }
            self.handle(action)
        }
    }

    private func toggleCompletion(id: UUID) {
        guard let current = tasks.first(where: { $0.id == id }) else { return }
        if case .inFlight = completionStatus[id] { return }

        completionGeneration += 1
        let generation = completionGeneration
        let client = taskClient
        var requested = current
        requested.isComplete.toggle()
        completionTasks[id]?.cancel()
        completionStatus[id] = .inFlight(generation: generation)
        rebuildRows()

        completionTasks[id] = Task { [weak self] in
            let action: InternalAction
            do {
                action = .completionSucceeded(try await client.updateTask(requested))
            } catch {
                action = .completionFailed(id)
            }
            guard !Task.isCancelled, let self,
                  self.completionStatus[id] == .inFlight(generation: generation) else { return }
            self.handle(action)
        }
    }

    // MARK: - Children

    private func handle(_ event: AddTaskViewModelEvent) {
        switch event {
        case .created(let item):
            mutationGeneration += 1
            if !tasks.contains(where: { $0.id == item.id }) {
                tasks.append(item)
            }
            state.phase = .content
            rebuildRows()
            dismissAdd()
        case .closeRequested:
            dismissAdd()
        }
    }

    private func handle(_ event: TaskDetailViewModelEvent) {
        switch event {
        case .dirtyChanged(let isDirty):
            state.isDetailDirty = isDirty
        case .updated(let item):
            mutationGeneration += 1
            if let index = tasks.firstIndex(where: { $0.id == item.id }) {
                tasks[index] = item
            }
            rebuildRows()
        case .deleted(let id):
            mutationGeneration += 1
            tasks.removeAll { $0.id == id }
            completionTasks[id]?.cancel()
            completionTasks[id] = nil
            completionStatus[id] = nil
            if tasks.isEmpty, state.phase == .content {
                state.phase = .empty
            }
            rebuildRows()
            popDetail()
        }
    }

    private func openDetail(id: UUID) {
        guard state.navigationPath.isEmpty,
              let item = tasks.first(where: { $0.id == id }) else { return }
        let child = withDependencies(from: self) {
            TaskDetailViewModel(state: TaskDetailViewState(task: item))
        }
        child.onEvent = { [weak self] in self?.handle($0) }
        detailViewModel = child
        state.isDetailDirty = false
        state.navigationPath = [.detail(id: id)]
    }

    private func popDetail() {
        state.navigationPath = []
        clearDetail()
    }

    private func clearDetail() {
        detailViewModel = nil
        state.isDetailDirty = false
        state.isDiscardConfirmationPresented = false
    }

    private func dismissAdd() {
        guard addViewModel != nil else { return }
        objectWillChange.send()
        addViewModel = nil
    }

    // MARK: - Rows

    private func rebuildRows() {
        state.rows = tasks.map { item in
            let status = completionStatus[item.id]
            let isInFlight: Bool
            let errorMessage: String?
            switch status {
            case .inFlight?:
                isInFlight = true
                errorMessage = nil
            case .failed?:
                isInFlight = false
                errorMessage = L10n.TaskBoard.completionError
            case nil:
                isInFlight = false
                errorMessage = nil
            }
            return TaskBoardRowState(
                id: item.id,
                title: item.title,
                priority: item.priority,
                priorityText: priorityText(item.priority),
                priorityAccessibilityLabel: priorityAccessibilityLabel(item.priority),
                isComplete: item.isComplete,
                isCompletionInFlight: isInFlight,
                completionAccessibilityLabel: item.isComplete
                    ? L10n.TaskBoard.markIncomplete
                    : L10n.TaskBoard.markComplete,
                completionErrorMessage: errorMessage
            )
        }
    }

    private func priorityText(_ priority: TaskPriority) -> String {
        switch priority {
        case .low: L10n.TaskBoard.lowPriority
        case .medium: L10n.TaskBoard.mediumPriority
        case .high: L10n.TaskBoard.highPriority
        }
    }

    private func priorityAccessibilityLabel(_ priority: TaskPriority) -> String {
        switch priority {
        case .low: L10n.TaskBoard.lowPriorityAccessibility
        case .medium: L10n.TaskBoard.mediumPriorityAccessibility
        case .high: L10n.TaskBoard.highPriorityAccessibility
        }
    }
}
