import Combine
import Foundation
import Dependencies
import L10n
import TaskClient
import Testing
@testable import TaskDetailFeature

@MainActor
struct TaskDetailViewModelTests {
    @Test("""
        Given a selected task,
        When the detail state is initialized,
        Then its editable fields and confirmed item match the task
        """)
    func stateStartsWithSelectedTaskFields() {
        let task = sampleTask()
        let sut = withDependencies {
            makeDependencies(&$0)
        } operation: {
            TaskDetailViewModel(state: TaskDetailViewState(task: task))
        }

        #expect(sut.state.task == task)
        #expect(sut.state.title == task.title)
        #expect(sut.state.notes == task.notes)
        #expect(sut.state.priority == task.priority)
        #expect(sut.state.isDirty == false)
        #expect(sut.state.canSave == false)
    }

    @Test("""
        Given a clean task draft,
        When fields change and are restored,
        Then dirty output is emitted only when the draft crosses the clean boundary
        """)
    func editsEmitDirtyTransitions() {
        let task = sampleTask()
        let sut = withDependencies {
            makeDependencies(&$0)
        } operation: {
            TaskDetailViewModel(state: TaskDetailViewState(task: task))
        }
        var events: [TaskDetailViewModelEvent] = []
        sut.onEvent = { events.append($0) }

        sut.trigger(.titleChanged("Updated title"))
        sut.trigger(.notesChanged("Updated notes"))
        sut.trigger(.titleChanged(task.title))
        #expect(sut.state.isDirty)

        sut.trigger(.notesChanged(task.notes))
        #expect(sut.state.isDirty == false)
        #expect(events == [.dirtyChanged(true), .dirtyChanged(false)])
    }

    @Test("""
        Given an edited task,
        When Save succeeds,
        Then the normalized draft is saved and updated is emitted without closing detail
        """)
    func saveSuccessEmitsUpdatedTask() async {
        let task = sampleTask()
        let submittedTask = LockIsolated<TaskItem?>(nil)
        let updatedTask = TaskItem(
            id: task.id,
            title: "Revised task",
            notes: "New notes",
            priority: .high,
            isComplete: task.isComplete
        )
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.updateTask = { submitted in
                submittedTask.withValue { $0 = submitted }
                return updatedTask
            }
        } operation: {
            TaskDetailViewModel(state: TaskDetailViewState(task: task))
        }
        var events: [TaskDetailViewModelEvent] = []
        sut.onEvent = { events.append($0) }

        sut.trigger(.titleChanged("  Revised task \n"))
        sut.trigger(.notesChanged("New notes"))
        sut.trigger(.priorityChanged(.high))
        sut.trigger(.saveTapped)
        await sut.writeTask?.value

        #expect(submittedTask.value == updatedTask)
        #expect(sut.state.task == updatedTask)
        #expect(sut.state.title == updatedTask.title)
        #expect(sut.state.notes == updatedTask.notes)
        #expect(sut.state.priority == updatedTask.priority)
        #expect(sut.state.isDirty == false)
        #expect(sut.state.inlineErrorMessage == nil)
        #expect(events == [
            .dirtyChanged(true),
            .dirtyChanged(false),
            .updated(updatedTask),
        ])
    }

    @Test("""
        Given an edited task and a failed update,
        When the user retries and the update succeeds,
        Then the draft is retained until success and updated is emitted
        """)
    func saveFailurePreservesDraftAndRetrySucceeds() async {
        let task = sampleTask()
        let updatedTask = TaskItem(
            id: task.id,
            title: "Retried title",
            notes: "Retried notes",
            priority: .low,
            isComplete: task.isComplete
        )
        let calls = LockIsolated(0)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.updateTask = { _ in
                let call = calls.withValue { $0 += 1; return $0 }
                if call == 1 { throw TaskClientError.unavailable }
                return updatedTask
            }
        } operation: {
            TaskDetailViewModel(state: TaskDetailViewState(task: task))
        }
        var events: [TaskDetailViewModelEvent] = []
        sut.onEvent = { events.append($0) }

        sut.trigger(.titleChanged("Retried title"))
        sut.trigger(.notesChanged("Retried notes"))
        sut.trigger(.priorityChanged(.low))
        sut.trigger(.saveTapped)
        await sut.writeTask?.value

        #expect(sut.state.task == task)
        #expect(sut.state.title == "Retried title")
        #expect(sut.state.notes == "Retried notes")
        #expect(sut.state.priority == .low)
        #expect(sut.state.isDirty)
        #expect(sut.state.inlineErrorMessage == L10n.TaskDetail.saveError)
        #expect(sut.state.canRetry)

        sut.trigger(.retryTapped)
        await sut.writeTask?.value

        #expect(calls.value == 2)
        #expect(sut.state.task == updatedTask)
        #expect(sut.state.inlineErrorMessage == nil)
        #expect(events.last == .updated(updatedTask))
    }

    @Test("""
        Given a task detail,
        When delete is requested and confirmed,
        Then deletion runs only after confirmation and emits the task identifier
        """)
    func deleteRequiresConfirmationAndEmitsDeleted() async {
        let task = sampleTask()
        let deletedIDs = LockIsolated<[UUID]>([])
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.deleteTask = { id in
                deletedIDs.withValue { $0.append(id) }
            }
        } operation: {
            TaskDetailViewModel(state: TaskDetailViewState(task: task))
        }
        var events: [TaskDetailViewModelEvent] = []
        sut.onEvent = { events.append($0) }

        sut.trigger(.deleteTapped)
        #expect(sut.state.isDeleteConfirmationPresented)
        #expect(deletedIDs.value.isEmpty)

        sut.trigger(.deleteCancelled)
        #expect(sut.state.isDeleteConfirmationPresented == false)
        #expect(deletedIDs.value.isEmpty)

        sut.trigger(.deleteTapped)
        sut.trigger(.deleteConfirmed)
        await sut.writeTask?.value

        #expect(deletedIDs.value == [task.id])
        #expect(events == [.deleted(task.id)])
    }

    @Test("""
        Given the delete alert was dismissed with Cancel,
        When the alert binding reports dismissal again,
        Then the view model publishes no further change
        """)
    func repeatedDeleteCancelDoesNotPublish() {
        let sut = withDependencies { makeDependencies(&$0) } operation: {
            TaskDetailViewModel(state: TaskDetailViewState(task: sampleTask()))
        }
        sut.trigger(.deleteTapped)
        sut.trigger(.deleteCancelled)
        var changes = 0
        let cancellable = sut.objectWillChange.sink { changes += 1 }

        sut.trigger(.deleteCancelled)

        #expect(changes == 0)
        #expect(sut.state.isDeleteConfirmationPresented == false)
        cancellable.cancel()
    }

    @Test("""
        Given delete is confirmed but the client fails,
        When the user retries,
        Then the task remains available until deletion succeeds
        """)
    func deleteFailurePreservesTaskAndRetrySucceeds() async {
        let task = sampleTask()
        let calls = LockIsolated(0)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.deleteTask = { _ in
                let call = calls.withValue { $0 += 1; return $0 }
                if call == 1 { throw TaskClientError.unavailable }
            }
        } operation: {
            TaskDetailViewModel(state: TaskDetailViewState(task: task))
        }
        var events: [TaskDetailViewModelEvent] = []
        sut.onEvent = { events.append($0) }

        sut.trigger(.deleteTapped)
        sut.trigger(.deleteConfirmed)
        await sut.writeTask?.value

        #expect(sut.state.task == task)
        #expect(sut.state.isDeleteConfirmationPresented == false)
        #expect(sut.state.inlineErrorMessage == L10n.TaskDetail.deleteError)
        #expect(sut.state.canRetry)
        #expect(events.isEmpty)

        sut.trigger(.retryTapped)
        await sut.writeTask?.value

        #expect(calls.value == 2)
        #expect(sut.state.task == task)
        #expect(sut.state.inlineErrorMessage == nil)
        #expect(events == [.deleted(task.id)])
    }
}

private func sampleTask() -> TaskItem {
    TaskItem(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        title: "Selected task",
        notes: "Current notes",
        priority: .medium,
        isComplete: true
    )
}

private func makeDependencies(_ dependencies: inout DependencyValues) {
    dependencies.taskClient.updateTask = { _ in throw TaskClientError.unavailable }
    dependencies.taskClient.deleteTask = { _ in throw TaskClientError.unavailable }
}

@MainActor
struct TaskDetailDueDateTests {
    private func utcDay(_ day: String) -> Date {
        try! Date("\(day)T00:00:00Z", strategy: .iso8601)
    }

    private func dueDateDependencies(
        _ dependencies: inout DependencyValues,
        update: (@Sendable (TaskItem) async throws -> TaskItem)? = nil
    ) {
        makeDependencies(&dependencies)
        // 2025-03-11 00:30 in Tokyo (still 2025-03-10 in UTC).
        dependencies.date.now = try! Date("2025-03-10T15:30:00Z", strategy: .iso8601)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        dependencies.calendar = calendar
        if let update { dependencies.taskClient.updateTask = update }
    }

    @Test("""
        Given a task without a due date,
        When the toggle is turned on and off,
        Then the local today is used and dirty follows the change
        """)
    func addingAndClearingDueDateTracksDirty() {
        let sut = withDependencies {
            dueDateDependencies(&$0)
        } operation: {
            TaskDetailViewModel(state: TaskDetailViewState(task: sampleTask()))
        }
        var events: [TaskDetailViewModelEvent] = []
        sut.onEvent = { events.append($0) }

        sut.trigger(.dueDateToggled(true))
        #expect(sut.state.dueDate == utcDay("2025-03-11"))
        #expect(sut.state.isDirty)

        sut.trigger(.dueDateToggled(false))
        #expect(sut.state.dueDate == nil)
        #expect(!sut.state.isDirty)
        #expect(events == [.dirtyChanged(true), .dirtyChanged(false)])
    }

    @Test("""
        Given a task with a due date,
        When the date is changed and changed back,
        Then dirty is set and cleared
        """)
    func changingDueDateTracksDirty() {
        var task = sampleTask()
        task.dueDate = utcDay("2025-03-20")
        let sut = withDependencies {
            dueDateDependencies(&$0)
        } operation: {
            TaskDetailViewModel(state: TaskDetailViewState(task: task))
        }
        #expect(sut.state.hasDueDate)

        sut.trigger(.dueDateChanged(try! Date("2025-03-21T09:00:00Z", strategy: .iso8601)))
        #expect(sut.state.dueDate == utcDay("2025-03-21"))
        #expect(sut.state.isDirty)

        sut.trigger(.dueDateChanged(utcDay("2025-03-20")))
        #expect(!sut.state.isDirty)
    }

    @Test("""
        Given a cleared due date,
        When Save succeeds,
        Then the update has no due date and the saved task becomes the clean baseline
        """)
    func saveSendsClearedDueDate() async {
        var task = sampleTask()
        task.dueDate = utcDay("2025-03-20")
        let submitted = LockIsolated<TaskItem?>(nil)
        let sut = withDependencies {
            dueDateDependencies(&$0, update: { item in
                submitted.setValue(item)
                return item
            })
        } operation: {
            TaskDetailViewModel(state: TaskDetailViewState(task: task))
        }

        sut.trigger(.dueDateToggled(false))
        sut.trigger(.saveTapped)
        await sut.writeTask?.value

        #expect(submitted.value?.dueDate == nil)
        #expect(sut.state.task.dueDate == nil)
        #expect(!sut.state.hasDueDate)
        #expect(!sut.state.isDirty)
    }
}
