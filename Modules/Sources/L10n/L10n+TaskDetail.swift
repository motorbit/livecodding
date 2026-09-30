import Foundation

public extension L10n {
    enum TaskDetail {
        public static var title: String {
            String(localized: "taskDetail.title", defaultValue: "Task Details", bundle: .module)
        }
        public static var titleField: String {
            String(localized: "taskDetail.titleField", defaultValue: "Title", bundle: .module)
        }
        public static var notesField: String {
            String(localized: "taskDetail.notesField", defaultValue: "Notes", bundle: .module)
        }
        public static var priorityField: String {
            String(localized: "taskDetail.priorityField", defaultValue: "Priority", bundle: .module)
        }
        public static var lowPriority: String {
            String(localized: "taskDetail.priority.low", defaultValue: "Low", bundle: .module)
        }
        public static var mediumPriority: String {
            String(localized: "taskDetail.priority.medium", defaultValue: "Medium", bundle: .module)
        }
        public static var highPriority: String {
            String(localized: "taskDetail.priority.high", defaultValue: "High", bundle: .module)
        }
        public static var save: String {
            String(localized: "taskDetail.save", defaultValue: "Save", bundle: .module)
        }
        public static var delete: String {
            String(localized: "taskDetail.delete", defaultValue: "Delete Task", bundle: .module)
        }
        public static var retry: String {
            String(localized: "taskDetail.retry", defaultValue: "Retry", bundle: .module)
        }
        public static var saveError: String {
            String(localized: "taskDetail.error.save", defaultValue: "Couldn't save changes. Try again.", bundle: .module)
        }
        public static var deleteError: String {
            String(localized: "taskDetail.error.delete", defaultValue: "Couldn't delete task. Try again.", bundle: .module)
        }
        public static var titleRequired: String {
            String(localized: "taskDetail.error.titleRequired", defaultValue: "Enter a title.", bundle: .module)
        }
        public static var deleteConfirmationTitle: String {
            String(localized: "taskDetail.deleteConfirmation.title", defaultValue: "Delete task?", bundle: .module)
        }
        public static var deleteConfirmationMessage: String {
            String(localized: "taskDetail.deleteConfirmation.message", defaultValue: "This task will be permanently deleted.", bundle: .module)
        }
        public static var cancel: String {
            String(localized: "taskDetail.cancel", defaultValue: "Cancel", bundle: .module)
        }
        public static var confirmDelete: String {
            String(localized: "taskDetail.deleteConfirmation.confirm", defaultValue: "Delete", bundle: .module)
        }
        public static var discardConfirmationTitle: String {
            String(localized: "taskDetail.discardConfirmation.title", defaultValue: "Discard changes?", bundle: .module)
        }
        public static var discardConfirmationMessage: String {
            String(localized: "taskDetail.discardConfirmation.message", defaultValue: "Your unsaved changes will be lost.", bundle: .module)
        }
        public static var discardConfirmationCancel: String {
            String(localized: "taskDetail.discardConfirmation.cancel", defaultValue: "Keep Editing", bundle: .module)
        }
        public static var discardConfirmationDiscard: String {
            String(localized: "taskDetail.discardConfirmation.discard", defaultValue: "Discard", bundle: .module)
        }
    }
}
