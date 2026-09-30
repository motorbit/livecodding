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
