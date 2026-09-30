import Foundation
import Dependencies
import L10n
import TaskClient
import Testing
@testable import AddTaskFeature

@MainActor
struct AddTaskViewModelTests {
    @Test("""
        Given a blank title,
        When Save is tapped,
        Then validation is shown and no request is made
        """)
    func blankTitleIsRejected() async {
        let spy = CreateTaskSpy(responses: [])
        let sut = makeViewModel(spy: spy)

        sut.trigger(.titleChanged(" \n\t "))
        sut.trigger(.saveTapped)
        await sut.saveTask?.value

        #expect(sut.state.errorMessage == L10n.AddTask.titleRequired)
        #expect(!sut.state.isSaving)
        #expect(await spy.receivedDrafts().isEmpty)
    }

    @Test("""
        Given a valid draft,
        When task creation succeeds,
        Then the trimmed draft is submitted and created is emitted
        """)
    func successfulSaveEmitsCreated() async {
        let task = makeTask(title: "New task")
        let spy = CreateTaskSpy(responses: [.success(task)])
        let sut = makeViewModel(spy: spy)
        var events: [AddTaskViewModelEvent] = []
        sut.onEvent = { events.append($0) }

        sut.trigger(.titleChanged("  New task \n"))
        sut.trigger(.notesChanged("Details"))
        sut.trigger(.priorityChanged(.high))
        sut.trigger(.saveTapped)
        await sut.saveTask?.value

        #expect(await spy.receivedDrafts() == [
            TaskDraft(title: "New task", notes: "Details", priority: .high),
        ])
        #expect(events == [.created(task)])
        #expect(!sut.state.isSaving)
    }

    @Test("""
        Given task creation fails,
        When Retry succeeds,
        Then the draft remains and the task is emitted
        """)
    func failedSaveRetainsDraftAndRetrySucceeds() async {
        let task = makeTask(title: "Kept draft")
        let spy = CreateTaskSpy(responses: [.failure(.unavailable), .success(task)])
        let sut = makeViewModel(spy: spy)
        var events: [AddTaskViewModelEvent] = []
        sut.onEvent = { events.append($0) }

        sut.trigger(.titleChanged("Kept draft"))
        sut.trigger(.notesChanged("Keep these notes"))
        sut.trigger(.priorityChanged(.low))
        sut.trigger(.saveTapped)
        await sut.saveTask?.value

        #expect(sut.state.taskTitle == "Kept draft")
        #expect(sut.state.notes == "Keep these notes")
        #expect(sut.state.priority == .low)
        #expect(sut.state.errorMessage == L10n.AddTask.saveError)
        #expect(sut.state.canRetry)
        #expect(events.isEmpty)

        sut.trigger(.retryTapped)
        await sut.saveTask?.value

        #expect(await spy.receivedDrafts().count == 2)
        #expect(events == [.created(task)])
        #expect(sut.state.errorMessage == nil)
        #expect(!sut.state.isSaving)
    }

    @Test("""
        Given Cancel is tapped,
        When the form is idle,
        Then closeRequested is emitted
        """)
    func cancelEmitsCloseRequested() {
        let sut = makeViewModel(spy: CreateTaskSpy(responses: []))
        var events: [AddTaskViewModelEvent] = []
        sut.onEvent = { events.append($0) }

        sut.trigger(.cancelTapped)

        #expect(events == [.closeRequested])
    }

    @Test("""
        Given another task has the same title,
        When the draft is saved,
        Then duplicate titles are accepted
        """)
    func duplicateTitlesAreAccepted() async {
        let first = makeTask(title: "Same title")
        let second = makeTask(title: "Same title")
        let spy = CreateTaskSpy(responses: [.success(first), .success(second)])
        let sut = makeViewModel(spy: spy)
        var events: [AddTaskViewModelEvent] = []
        sut.onEvent = { events.append($0) }

        sut.trigger(.titleChanged("Same title"))
        sut.trigger(.saveTapped)
        await sut.saveTask?.value
        sut.trigger(.saveTapped)
        await sut.saveTask?.value

        #expect(events == [.created(first), .created(second)])
        #expect(await spy.receivedDrafts().map(\.title) == ["Same title", "Same title"])
    }

    private func makeViewModel(spy: CreateTaskSpy) -> AddTaskViewModel {
        withDependencies {
            makeDependencies(&$0)
            $0.taskClient.createTask = { draft in
                try await spy.createTask(draft)
            }
        } operation: {
            AddTaskViewModel()
        }
    }

    private func makeTask(title: String) -> TaskItem {
        TaskItem(id: UUID(), title: title, priority: .medium)
    }
}

private actor CreateTaskSpy {
    private let responses: [Result<TaskItem, TaskClientError>]
    private var drafts: [TaskDraft] = []

    init(responses: [Result<TaskItem, TaskClientError>]) {
        self.responses = responses
    }

    func createTask(_ draft: TaskDraft) throws -> TaskItem {
        drafts.append(draft)
        let index = drafts.count - 1
        guard responses.indices.contains(index) else {
            throw TaskClientError.unavailable
        }
        return try responses[index].get()
    }

    func receivedDrafts() -> [TaskDraft] {
        drafts
    }
}

private func makeDependencies(_ dependencies: inout DependencyValues) {
    dependencies.taskClient = TaskClient()
}

@MainActor
struct AddTaskDueDateTests {
    // 2025-03-10 23:30 in Los Angeles (already 2025-03-11 in UTC).
    private let now = try! Date("2025-03-11T06:30:00Z", strategy: .iso8601)

    private func utcDay(_ day: String) -> Date {
        try! Date("\(day)T00:00:00Z", strategy: .iso8601)
    }

    private func dueDateDependencies(_ dependencies: inout DependencyValues, spy: CreateTaskSpy) {
        makeDependencies(&dependencies)
        dependencies.date.now = now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        dependencies.calendar = calendar
        dependencies.taskClient.createTask = { try await spy.createTask($0) }
    }

    @Test("""
        Given the Add form,
        When the due-date toggle is turned on,
        Then the date defaults to the local today as a UTC day
        """)
    func toggleOnDefaultsToLocalToday() {
        let sut = withDependencies {
            dueDateDependencies(&$0, spy: CreateTaskSpy(responses: []))
        } operation: { AddTaskViewModel() }

        sut.trigger(.dueDateToggled(true))

        #expect(sut.state.hasDueDate)
        #expect(sut.state.dueDate == utcDay("2025-03-10"))
    }

    @Test("""
        Given a picked due date,
        When Save succeeds,
        Then the draft carries the normalized UTC day
        """)
    func savedDraftCarriesDueDate() async {
        let spy = CreateTaskSpy(responses: [.success(TaskItem(id: UUID(), title: "T", priority: .medium))])
        let sut = withDependencies {
            dueDateDependencies(&$0, spy: spy)
        } operation: { AddTaskViewModel() }

        sut.trigger(.titleChanged("T"))
        sut.trigger(.dueDateToggled(true))
        sut.trigger(.dueDateChanged(try! Date("2025-04-02T13:00:00Z", strategy: .iso8601)))
        sut.trigger(.saveTapped)
        await sut.saveTask?.value

        #expect(await spy.receivedDrafts() == [
            TaskDraft(title: "T", priority: .medium, dueDate: utcDay("2025-04-02")),
        ])
    }

    @Test("""
        Given a due date was set,
        When the toggle is turned off and Save succeeds,
        Then no due date is sent and later picker changes are ignored
        """)
    func toggleOffClearsDueDate() async {
        let spy = CreateTaskSpy(responses: [.success(TaskItem(id: UUID(), title: "T", priority: .medium))])
        let sut = withDependencies {
            dueDateDependencies(&$0, spy: spy)
        } operation: { AddTaskViewModel() }

        sut.trigger(.titleChanged("T"))
        sut.trigger(.dueDateToggled(true))
        sut.trigger(.dueDateToggled(false))
        sut.trigger(.dueDateChanged(utcDay("2025-04-02")))
        #expect(sut.state.dueDate == nil)

        sut.trigger(.saveTapped)
        await sut.saveTask?.value

        #expect(await spy.receivedDrafts() == [TaskDraft(title: "T", priority: .medium)])
    }
}
