import Foundation
import L10n
import TaskClient

public enum TaskBoardPhase: Equatable {
    case loading
    case empty
    case failed
    case content
}

public struct TaskBoardRowState: Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var priority: TaskPriority
    public var priorityText: String
    public var priorityAccessibilityLabel: String
    public var isComplete: Bool
    /// A completion or delete request for this row is in flight; its controls are disabled.
    public var isInFlight: Bool
    public var completionAccessibilityLabel: String
    /// Inline error for the row's last failed operation; Retry sends `.rowRetryTapped`.
    public var errorMessage: String?

    public init(
        id: UUID,
        title: String,
        priority: TaskPriority,
        priorityText: String,
        priorityAccessibilityLabel: String,
        isComplete: Bool,
        isInFlight: Bool,
        completionAccessibilityLabel: String,
        errorMessage: String?
    ) {
        self.id = id
        self.title = title
        self.priority = priority
        self.priorityText = priorityText
        self.priorityAccessibilityLabel = priorityAccessibilityLabel
        self.isComplete = isComplete
        self.isInFlight = isInFlight
        self.completionAccessibilityLabel = completionAccessibilityLabel
        self.errorMessage = errorMessage
    }
}

/// Local list order; ties keep API order.
public enum TaskSortOrder: CaseIterable, Equatable, Hashable {
    /// API order (new tasks appended).
    case `default`
    /// High → Low.
    case priority
    /// Incomplete first.
    case status
}

public struct TaskBoardSortOption: Equatable, Identifiable {
    public var order: TaskSortOrder
    public var title: String
    public var id: TaskSortOrder { order }

    public init(order: TaskSortOrder, title: String) {
        self.order = order
        self.title = title
    }
}

/// Shown while a swiped deletion can still be undone.
public struct TaskBoardUndoState: Equatable {
    public var message: String

    public init(message: String) {
        self.message = message
    }
}

public struct TaskBoardViewState: Equatable {
    public var phase: TaskBoardPhase
    public var rows: [TaskBoardRowState]
    public var reloadErrorMessage: String?
    public var navigationPath: [TaskBoardRoute]
    public var isDetailDirty: Bool
    public var isDiscardConfirmationPresented: Bool
    public var undo: TaskBoardUndoState?
    public var searchText: String
    public var sortOrder: TaskSortOrder
    /// Tasks exist but none match `searchText`.
    public var isNoResults: Bool

    public var title: String
    public var addTitle: String
    public var loadingMessage: String
    public var emptyTitle: String
    public var emptyMessage: String
    public var loadErrorMessage: String
    public var retryTitle: String
    public var backTitle: String
    public var openDetailHint: String
    public var deleteTitle: String
    public var undoTitle: String
    public var searchPrompt: String
    public var sortTitle: String
    public var sortOptions: [TaskBoardSortOption]
    public var noResultsTitle: String
    public var noResultsMessage: String
    public var discardTitle: String
    public var discardMessage: String
    public var discardConfirmTitle: String
    public var discardCancelTitle: String

    public init(
        phase: TaskBoardPhase = .loading,
        rows: [TaskBoardRowState] = [],
        reloadErrorMessage: String? = nil,
        navigationPath: [TaskBoardRoute] = [],
        isDetailDirty: Bool = false,
        isDiscardConfirmationPresented: Bool = false,
        undo: TaskBoardUndoState? = nil,
        searchText: String = "",
        sortOrder: TaskSortOrder = .default,
        isNoResults: Bool = false,
        title: String = L10n.TaskBoard.title,
        addTitle: String = L10n.TaskBoard.add,
        loadingMessage: String = L10n.TaskBoard.loading,
        emptyTitle: String = L10n.TaskBoard.emptyTitle,
        emptyMessage: String = L10n.TaskBoard.emptyMessage,
        loadErrorMessage: String = L10n.TaskBoard.loadError,
        retryTitle: String = L10n.TaskBoard.retry,
        backTitle: String = L10n.TaskBoard.back,
        openDetailHint: String = L10n.TaskBoard.openDetailHint,
        deleteTitle: String = L10n.TaskBoard.delete,
        undoTitle: String = L10n.TaskBoard.undo,
        searchPrompt: String = L10n.TaskBoard.searchPrompt,
        sortTitle: String = L10n.TaskBoard.sort,
        sortOptions: [TaskBoardSortOption] = [
            TaskBoardSortOption(order: .default, title: L10n.TaskBoard.sortDefault),
            TaskBoardSortOption(order: .priority, title: L10n.TaskBoard.sortPriority),
            TaskBoardSortOption(order: .status, title: L10n.TaskBoard.sortStatus),
        ],
        noResultsTitle: String = L10n.TaskBoard.noResultsTitle,
        noResultsMessage: String = L10n.TaskBoard.noResultsMessage,
        discardTitle: String = L10n.TaskDetail.discardConfirmationTitle,
        discardMessage: String = L10n.TaskDetail.discardConfirmationMessage,
        discardConfirmTitle: String = L10n.TaskDetail.discardConfirmationDiscard,
        discardCancelTitle: String = L10n.TaskDetail.discardConfirmationCancel
    ) {
        self.phase = phase
        self.rows = rows
        self.reloadErrorMessage = reloadErrorMessage
        self.navigationPath = navigationPath
        self.isDetailDirty = isDetailDirty
        self.isDiscardConfirmationPresented = isDiscardConfirmationPresented
        self.undo = undo
        self.searchText = searchText
        self.sortOrder = sortOrder
        self.isNoResults = isNoResults
        self.title = title
        self.addTitle = addTitle
        self.loadingMessage = loadingMessage
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.loadErrorMessage = loadErrorMessage
        self.retryTitle = retryTitle
        self.backTitle = backTitle
        self.openDetailHint = openDetailHint
        self.deleteTitle = deleteTitle
        self.undoTitle = undoTitle
        self.searchPrompt = searchPrompt
        self.sortTitle = sortTitle
        self.sortOptions = sortOptions
        self.noResultsTitle = noResultsTitle
        self.noResultsMessage = noResultsMessage
        self.discardTitle = discardTitle
        self.discardMessage = discardMessage
        self.discardConfirmTitle = discardConfirmTitle
        self.discardCancelTitle = discardCancelTitle
    }
}
