import Foundation

public enum TaskBoardViewEvent {
    case onAppear
    case retryTapped
    case refreshRequested
    case addTapped
    case addDismissed
    case taskTapped(UUID)
    case completionToggled(UUID)
    case completionRetryTapped(UUID)
    case navigationPathChanged([TaskBoardRoute])
    case detailBackTapped
    case discardConfirmed
    case discardCancelled
}
