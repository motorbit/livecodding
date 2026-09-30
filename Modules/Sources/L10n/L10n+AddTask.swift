import Foundation

public extension L10n {
    enum AddTask {
        public static var title: String {
            String(localized: "addTask.title", defaultValue: "Add Task", bundle: .module)
        }
        public static var titleLabel: String {
            String(localized: "addTask.titleLabel", defaultValue: "Title", bundle: .module)
        }
        public static var titlePlaceholder: String {
            String(localized: "addTask.titlePlaceholder", defaultValue: "What needs to be done?", bundle: .module)
        }
        public static var dueDateToggle: String {
            String(localized: "addTask.dueDate.toggle", defaultValue: "Add due date", bundle: .module)
        }
        public static var dueDateLabel: String {
            String(localized: "addTask.dueDate.label", defaultValue: "Due date", bundle: .module)
        }
        public static var notesLabel: String {
            String(localized: "addTask.notesLabel", defaultValue: "Notes (optional)", bundle: .module)
        }
        public static var notesPlaceholder: String {
            String(localized: "addTask.notesPlaceholder", defaultValue: "Add details", bundle: .module)
        }
        public static var priorityLabel: String {
            String(localized: "addTask.priorityLabel", defaultValue: "Priority", bundle: .module)
        }
        public static var lowPriority: String {
            String(localized: "addTask.priority.low", defaultValue: "Low", bundle: .module)
        }
        public static var mediumPriority: String {
            String(localized: "addTask.priority.medium", defaultValue: "Medium", bundle: .module)
        }
        public static var highPriority: String {
            String(localized: "addTask.priority.high", defaultValue: "High", bundle: .module)
        }
        public static var save: String {
            String(localized: "addTask.save", defaultValue: "Save", bundle: .module)
        }
        public static var cancel: String {
            String(localized: "addTask.cancel", defaultValue: "Cancel", bundle: .module)
        }
        public static var titleRequired: String {
            String(localized: "addTask.titleRequired", defaultValue: "Enter a title.", bundle: .module)
        }
        public static var saveError: String {
            String(localized: "addTask.saveError", defaultValue: "Couldn't save the task. Try again.", bundle: .module)
        }
        public static var retry: String {
            String(localized: "addTask.retry", defaultValue: "Retry", bundle: .module)
        }
    }
}
