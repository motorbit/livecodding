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
    public var isCompletionInFlight: Bool
    public var completionAccessibilityLabel: String
    public var completionErrorMessage: String?

    public init(
        id: UUID,
        title: String,
        priority: TaskPriority,
        priorityText: String,
        priorityAccessibilityLabel: String,
        isComplete: Bool,
        isCompletionInFlight: Bool,
        completionAccessibilityLabel: String,
        completionErrorMessage: String?
    ) {
        self.id = id
        self.title = title
        self.priority = priority
        self.priorityText = priorityText
        self.priorityAccessibilityLabel = priorityAccessibilityLabel
        self.isComplete = isComplete
        self.isCompletionInFlight = isCompletionInFlight
        self.completionAccessibilityLabel = completionAccessibilityLabel
        self.completionErrorMessage = completionErrorMessage
    }
}

public struct TaskBoardViewState: Equatable {
    public var phase: TaskBoardPhase
    public var rows: [TaskBoardRowState]
    public var reloadErrorMessage: String?
    public var navigationPath: [TaskBoardRoute]
    public var isDetailDirty: Bool
    public var isDiscardConfirmationPresented: Bool

    public var title: String
    public var addTitle: String
    public var loadingMessage: String
    public var emptyTitle: String
    public var emptyMessage: String
    public var loadErrorMessage: String
    public var retryTitle: String
    public var backTitle: String
    public var openDetailHint: String
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
        title: String = L10n.TaskBoard.title,
        addTitle: String = L10n.TaskBoard.add,
        loadingMessage: String = L10n.TaskBoard.loading,
        emptyTitle: String = L10n.TaskBoard.emptyTitle,
        emptyMessage: String = L10n.TaskBoard.emptyMessage,
        loadErrorMessage: String = L10n.TaskBoard.loadError,
        retryTitle: String = L10n.TaskBoard.retry,
        backTitle: String = L10n.TaskBoard.back,
        openDetailHint: String = L10n.TaskBoard.openDetailHint,
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
        self.title = title
        self.addTitle = addTitle
        self.loadingMessage = loadingMessage
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.loadErrorMessage = loadErrorMessage
        self.retryTitle = retryTitle
        self.backTitle = backTitle
        self.openDetailHint = openDetailHint
        self.discardTitle = discardTitle
        self.discardMessage = discardMessage
        self.discardConfirmTitle = discardConfirmTitle
        self.discardCancelTitle = discardCancelTitle
    }
}
