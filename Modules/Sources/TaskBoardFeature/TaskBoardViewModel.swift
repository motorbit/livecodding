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
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.date) private var date
    @Dependency(\.calendar) private var calendar
    @Dependency(\.locale) private var locale

    static let undoWindow: Duration = .seconds(4)

    var loadTask: Task<Void, Never>?
    /// One in-flight completion or delete request per row.
    var rowTasks: [UUID: Task<Void, Never>] = [:]
    var undoTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var rowGeneration = 0
    private var undoGeneration = 0
    private var mutationGeneration = 0
    private var tasks: [TaskItem] = []
    private var rowStatus: [UUID: RowStatus] = [:]
    /// Swiped row that can still be undone. Not sent to the API yet.
    private var pendingDeletion: PendingDeletion?
    /// Swiped rows whose delete request is in flight; restored at `index` if it fails.
    private var hiddenDeletions: [UUID: HiddenRow] = [:]

    private enum RowStatus: Equatable {
        case completionInFlight(generation: Int)
        case completionFailed
        case deletionInFlight(generation: Int)
        case deletionFailed
    }

    private struct HiddenRow {
        let item: TaskItem
        let index: Int
    }

    private struct PendingDeletion {
        let row: HiddenRow
        let generation: Int
    }

    public init(state: TaskBoardViewState = TaskBoardViewState()) {
        self.state = state
    }

    deinit {
        loadTask?.cancel()
        undoTask?.cancel()
        rowTasks.values.forEach { $0.cancel() }
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
        case .completionToggled(let id):
            toggleCompletion(id: id)
        case .rowRetryTapped(let id):
            switch rowStatus[id] {
            case .completionFailed?:
                toggleCompletion(id: id)
            case .deletionFailed?:
                guard tasks.contains(where: { $0.id == id }) else { return }
                sendDelete(id: id)
            case .completionInFlight?, .deletionInFlight?, nil:
                break
            }
        case .deleteSwiped(let id):
            swipeDelete(id: id)
        case .searchTextChanged(let text):
            guard text != state.searchText else { return }
            state.searchText = text
            rebuildRows()
        case .dayMayHaveChanged:
            rebuildRows()
        case .sortChanged(let order):
            guard order != state.sortOrder else { return }
            state.sortOrder = order
            rebuildRows()
        case .undoTapped:
            undoPendingDeletion()
        case .navigationPathChanged(let path):
            guard path != state.navigationPath else { return }
            if path.isEmpty, detailViewModel != nil, state.isDetailDirty {
                // Keep the pushed route until the user explicitly discards.
                if !state.isDiscardConfirmationPresented { state.isDiscardConfirmationPresented = true }
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
            // The alert binding also reports dismissal after a button action, inside a view update.
            guard state.isDiscardConfirmationPresented else { return }
            state.isDiscardConfirmationPresented = false
        }
    }

    // MARK: - Effects

    private enum InternalAction {
        case loaded([TaskItem])
        case loadFailed
        case completionSucceeded(TaskItem)
        case completionFailed(UUID)
        case undoWindowExpired
        case deletionSucceeded(UUID)
        case deletionFailed(UUID)
    }

    private func handle(_ action: InternalAction) {
        switch action {
        case .loaded(let items):
            var hidden = Set(hiddenDeletions.keys)
            if let pendingDeletion { hidden.insert(pendingDeletion.row.item.id) }
            tasks = items.filter { !hidden.contains($0.id) }
            let ids = Set(items.map(\.id)).union(hidden)
            rowStatus = rowStatus.filter { ids.contains($0.key) }
            state.reloadErrorMessage = nil
            state.phase = tasks.isEmpty ? .empty : .content
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
            rowStatus[item.id] = nil
            rowTasks[item.id] = nil
            if let index = tasks.firstIndex(where: { $0.id == item.id }) {
                tasks[index] = item
            }
            rebuildRows()
        case .completionFailed(let id):
            rowStatus[id] = .completionFailed
            rowTasks[id] = nil
            rebuildRows()
        case .undoWindowExpired:
            commitPendingDeletion()
        case .deletionSucceeded(let id):
            mutationGeneration += 1
            rowStatus[id] = nil
            rowTasks[id] = nil
            hiddenDeletions[id] = nil
            tasks.removeAll { $0.id == id }
            updatePhaseAfterRemoval()
            rebuildRows()
            if detailViewModel?.state.task.id == id {
                popDetail()
            }
        case .deletionFailed(let id):
            rowStatus[id] = .deletionFailed
            rowTasks[id] = nil
            if let row = hiddenDeletions.removeValue(forKey: id) {
                restore(row)
            }
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
        guard let current = tasks.first(where: { $0.id == id }), !isInFlight(id) else { return }

        rowGeneration += 1
        let generation = rowGeneration
        let client = taskClient
        var requested = current
        requested.isComplete.toggle()
        rowTasks[id]?.cancel()
        rowStatus[id] = .completionInFlight(generation: generation)
        rebuildRows()

        rowTasks[id] = Task { [weak self] in
            let action: InternalAction
            do {
                action = .completionSucceeded(try await client.updateTask(requested))
            } catch {
                action = .completionFailed(id)
            }
            guard !Task.isCancelled, let self,
                  self.rowStatus[id] == .completionInFlight(generation: generation) else { return }
            self.handle(action)
        }
    }

    // MARK: - Swipe to delete (deferred, undoable)

    private func swipeDelete(id: UUID) {
        guard tasks.contains(where: { $0.id == id }), !isInFlight(id) else { return }
        commitPendingDeletion()
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }

        let item = tasks.remove(at: index)
        rowStatus[id] = nil
        undoGeneration += 1
        let generation = undoGeneration
        pendingDeletion = PendingDeletion(row: HiddenRow(item: item, index: index), generation: generation)
        state.undo = TaskBoardUndoState(message: L10n.TaskBoard.deletedMessage(item.title))
        updatePhaseAfterRemoval()
        rebuildRows()

        let clock = clock
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            do {
                try await clock.sleep(for: Self.undoWindow)
            } catch {
                return
            }
            guard !Task.isCancelled, let self,
                  self.pendingDeletion?.generation == generation else { return }
            self.handle(.undoWindowExpired)
        }
    }

    private func undoPendingDeletion() {
        guard let pending = pendingDeletion else { return }
        clearPendingDeletion()
        restore(pending.row)
        rebuildRows()
    }

    private func commitPendingDeletion() {
        guard let pending = pendingDeletion else { return }
        clearPendingDeletion()
        hiddenDeletions[pending.row.item.id] = pending.row
        sendDelete(id: pending.row.item.id)
    }

    private func clearPendingDeletion() {
        pendingDeletion = nil
        undoTask?.cancel()
        undoTask = nil
        state.undo = nil
    }

    private func sendDelete(id: UUID) {
        rowGeneration += 1
        let generation = rowGeneration
        let client = taskClient
        rowTasks[id]?.cancel()
        rowStatus[id] = .deletionInFlight(generation: generation)
        rebuildRows()

        rowTasks[id] = Task { [weak self] in
            let action: InternalAction
            do {
                try await client.deleteTask(id: id)
                action = .deletionSucceeded(id)
            } catch {
                action = .deletionFailed(id)
            }
            guard !Task.isCancelled, let self,
                  self.rowStatus[id] == .deletionInFlight(generation: generation) else { return }
            self.handle(action)
        }
    }

    private func restore(_ row: HiddenRow) {
        guard !tasks.contains(where: { $0.id == row.item.id }) else { return }
        tasks.insert(row.item, at: min(row.index, tasks.count))
        if state.phase == .empty { state.phase = .content }
    }

    private func updatePhaseAfterRemoval() {
        if tasks.isEmpty, state.phase == .content {
            state.phase = .empty
        }
    }

    private func isInFlight(_ id: UUID) -> Bool {
        switch rowStatus[id] {
        case .completionInFlight?, .deletionInFlight?: true
        case .completionFailed?, .deletionFailed?, nil: false
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
            let hasLoadedList: Bool
            switch state.phase {
            case .content, .empty: hasLoadedList = true
            case .loading, .failed: hasLoadedList = false
            }
            state.phase = .content
            rebuildRows()
            dismissAdd()
            // The local list holds only the new task, so fetch the rest; a failure shows the reload banner.
            if !hasLoadedList { load() }
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
            rowTasks[id]?.cancel()
            rowTasks[id] = nil
            rowStatus[id] = nil
            updatePhaseAfterRemoval()
            rebuildRows()
            popDetail()
        }
    }

    private func openDetail(id: UUID) {
        // Detail copies the task; opening it mid-request would save a stale snapshot.
        guard state.navigationPath.isEmpty, !isInFlight(id),
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
        let query = state.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = sorted(tasks, by: state.sortOrder).filter { item in
            query.isEmpty || item.title.localizedStandardContains(query)
        }
        state.isNoResults = !tasks.isEmpty && visible.isEmpty
        let today = visible.contains { $0.dueDate != nil }
            ? DueDay.day(containing: date.now, in: calendar)
            : nil
        state.rows = visible.map { item in
            let due = today.flatMap { today in
                item.dueDate.map { dueDescription(for: $0, isComplete: item.isComplete, today: today) }
            }
            let errorMessage: String?
            switch rowStatus[item.id] {
            case .completionFailed?:
                errorMessage = L10n.TaskBoard.completionError
            case .deletionFailed?:
                errorMessage = L10n.TaskBoard.deleteError
            case .completionInFlight?, .deletionInFlight?, nil:
                errorMessage = nil
            }
            return TaskBoardRowState(
                id: item.id,
                title: item.title,
                priority: item.priority,
                priorityText: priorityText(item.priority),
                priorityAccessibilityLabel: priorityAccessibilityLabel(item.priority),
                isComplete: item.isComplete,
                isInFlight: isInFlight(item.id),
                completionAccessibilityLabel: item.isComplete
                    ? L10n.TaskBoard.markIncomplete
                    : L10n.TaskBoard.markComplete,
                errorMessage: errorMessage,
                dueText: due?.text,
                isOverdue: due?.isOverdue ?? false
            )
        }
    }

    private func dueDescription(
        for dueDate: Date,
        isComplete: Bool,
        today: Date
    ) -> (text: String, isOverdue: Bool) {
        let days = DueDay.days(from: today, to: dueDate)
        switch days {
        case 0:
            return (L10n.TaskBoard.dueToday, false)
        case 1:
            return (L10n.TaskBoard.dueTomorrow, false)
        case 2...:
            return (L10n.TaskBoard.dueInDays(days, locale: locale), false)
        default:
            if !isComplete {
                return (L10n.TaskBoard.overdueByDays(-days, locale: locale), true)
            }
            return days == -1
                ? (L10n.TaskBoard.dueYesterday, false)
                : (L10n.TaskBoard.dueDaysAgo(-days, locale: locale), false)
        }
    }

    private func sorted(_ items: [TaskItem], by order: TaskSortOrder) -> [TaskItem] {
        let rank: (TaskItem) -> Int
        switch order {
        case .default:
            return items
        case .priority:
            rank = { item in
                switch item.priority {
                case .high: 0
                case .medium: 1
                case .low: 2
                }
            }
        case .status:
            rank = { $0.isComplete ? 1 : 0 }
        }
        return items.enumerated()
            .sorted { lhs, rhs in
                let (l, r) = (rank(lhs.element), rank(rhs.element))
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map(\.element)
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
