import Foundation

public enum TaskBoardViewEvent {
    case onAppear
    case retryTapped
    /// Sent by `TaskBoardViewModel.refresh()`; Views call `refresh()` from `.refreshable`.
    case refreshRequested
    case addTapped
    case addDismissed
    case taskTapped(UUID)
    case completionToggled(UUID)
    /// Retries the row's last failed operation (completion or delete).
    case rowRetryTapped(UUID)
    case deleteSwiped(UUID)
    case undoTapped
    case searchTextChanged(String)
    /// The scene became active or the system day changed; relative due text is recomputed.
    case dayMayHaveChanged
    case sortChanged(TaskSortOrder)
    case navigationPathChanged([TaskBoardRoute])
    case detailBackTapped
    case discardConfirmed
    case discardCancelled
}
