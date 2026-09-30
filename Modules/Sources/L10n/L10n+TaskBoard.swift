import Foundation

public extension L10n {
    enum TaskBoard {
        public static var title: String {
            String(localized: "taskBoard.title", defaultValue: "Task Board", bundle: .module)
        }
        public static var add: String {
            String(localized: "taskBoard.add", defaultValue: "Add Task", bundle: .module)
        }
        public static var loading: String {
            String(localized: "taskBoard.loading", defaultValue: "Loading tasks…", bundle: .module)
        }
        public static var emptyTitle: String {
            String(localized: "taskBoard.empty.title", defaultValue: "No tasks yet", bundle: .module)
        }
        public static var emptyMessage: String {
            String(localized: "taskBoard.empty.message", defaultValue: "Add a task to get started.", bundle: .module)
        }
        public static var loadError: String {
            String(localized: "taskBoard.error.load", defaultValue: "Couldn't load tasks.", bundle: .module)
        }
        public static var reloadError: String {
            String(localized: "taskBoard.error.reload", defaultValue: "Couldn't refresh tasks. Showing the last loaded list.", bundle: .module)
        }
        public static var completionError: String {
            String(localized: "taskBoard.error.completion", defaultValue: "Couldn't update this task.", bundle: .module)
        }
        public static var retry: String {
            String(localized: "taskBoard.retry", defaultValue: "Retry", bundle: .module)
        }
        public static var back: String {
            String(localized: "taskBoard.back", defaultValue: "Back", bundle: .module)
        }
        public static var lowPriority: String {
            String(localized: "taskBoard.priority.low", defaultValue: "Low", bundle: .module)
        }
        public static var mediumPriority: String {
            String(localized: "taskBoard.priority.medium", defaultValue: "Medium", bundle: .module)
        }
        public static var highPriority: String {
            String(localized: "taskBoard.priority.high", defaultValue: "High", bundle: .module)
        }
        public static var lowPriorityAccessibility: String {
            String(localized: "taskBoard.priority.low.accessibility", defaultValue: "Low priority", bundle: .module)
        }
        public static var mediumPriorityAccessibility: String {
            String(localized: "taskBoard.priority.medium.accessibility", defaultValue: "Medium priority", bundle: .module)
        }
        public static var highPriorityAccessibility: String {
            String(localized: "taskBoard.priority.high.accessibility", defaultValue: "High priority", bundle: .module)
        }
        public static var markComplete: String {
            String(localized: "taskBoard.completion.markComplete", defaultValue: "Mark as complete", bundle: .module)
        }
        public static var markIncomplete: String {
            String(localized: "taskBoard.completion.markIncomplete", defaultValue: "Mark as incomplete", bundle: .module)
        }
        public static var delete: String {
            String(localized: "taskBoard.row.delete", defaultValue: "Delete", bundle: .module)
        }
        public static var undo: String {
            String(localized: "taskBoard.undo.action", defaultValue: "Undo", bundle: .module)
        }
        public static func deletedMessage(_ title: String) -> String {
            String(localized: "taskBoard.undo.message \(title)", bundle: .module)
        }
        public static var deleteError: String {
            String(localized: "taskBoard.error.delete", defaultValue: "Couldn't delete this task.", bundle: .module)
        }
        public static var sort: String {
            String(localized: "taskBoard.sort.title", defaultValue: "Sort", bundle: .module)
        }
        public static var sortDefault: String {
            String(localized: "taskBoard.sort.default", defaultValue: "Default", bundle: .module)
        }
        public static var sortPriority: String {
            String(localized: "taskBoard.sort.priority", defaultValue: "Priority", bundle: .module)
        }
        public static var sortStatus: String {
            String(localized: "taskBoard.sort.status", defaultValue: "Status", bundle: .module)
        }
        public static var searchPrompt: String {
            String(localized: "taskBoard.search.prompt", defaultValue: "Search tasks", bundle: .module)
        }
        public static var noResultsTitle: String {
            String(localized: "taskBoard.search.noResults.title", defaultValue: "No matching tasks", bundle: .module)
        }
        public static var noResultsMessage: String {
            String(localized: "taskBoard.search.noResults.message", defaultValue: "Try a different title.", bundle: .module)
        }
        public static var dueToday: String {
            String(localized: "taskBoard.due.today", defaultValue: "Due today", bundle: .module)
        }
        public static var dueTomorrow: String {
            String(localized: "taskBoard.due.tomorrow", defaultValue: "Due tomorrow", bundle: .module)
        }
        public static var dueYesterday: String {
            String(localized: "taskBoard.due.yesterday", defaultValue: "Due yesterday", bundle: .module)
        }
        public static func dueInDays(_ days: Int, locale: Locale) -> String {
            String(localized: "taskBoard.due.inDays \(days)", bundle: .module, locale: locale)
        }
        public static func dueDaysAgo(_ days: Int, locale: Locale) -> String {
            String(localized: "taskBoard.due.daysAgo \(days)", bundle: .module, locale: locale)
        }
        public static func overdueByDays(_ days: Int, locale: Locale) -> String {
            String(localized: "taskBoard.due.overdue \(days)", bundle: .module, locale: locale)
        }
        public static var openDetailHint: String {
            String(localized: "taskBoard.row.openHint", defaultValue: "Opens task details", bundle: .module)
        }
    }
}
