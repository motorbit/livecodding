@testable import AddTaskFeature
import Dependencies
import Foundation
import L10n
import TaskClient
import TaskDetailFeature
import Testing
@testable import TaskBoardFeature

private struct TestError: Error {}

private func makeDependencies(_ dependencies: inout DependencyValues) {
    dependencies.taskClient.fetchTasks = { TaskItem.samples }
    dependencies.taskClient.updateTask = { $0 }
}

private let firstID = TaskItem.samples[0].id
private let dentistID = TaskItem.samples[2].id

@MainActor
struct TaskBoardLoadingTests {
    @Test("""
        Given a new board,
        When it appears,
        Then it shows loading and then the seeded tasks in order
        """)
    func loadSuccessShowsOrderedContent() async {
        let sut = withDependencies { makeDependencies(&$0) } operation: { TaskBoardViewModel() }
        #expect(sut.state.phase == .loading)

        sut.trigger(.onAppear)
        await sut.loadTask?.value

        #expect(sut.state.phase == .content)
        #expect(sut.state.rows.map(\.id) == TaskItem.samples.map(\.id))
        #expect(sut.state.rows[0].priorityText == L10n.TaskBoard.highPriority)
        #expect(sut.state.rows[0].priorityAccessibilityLabel == L10n.TaskBoard.highPriorityAccessibility)
        #expect(sut.state.rows[2].isComplete)
        #expect(sut.state.rows[2].completionAccessibilityLabel == L10n.TaskBoard.markIncomplete)
    }

    @Test("""
        Given the board already loaded,
        When it appears again,
        Then it does not reload
        """)
    func secondAppearDoesNotReload() async {
        let calls = LockIsolated(0)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.fetchTasks = {
                calls.withValue { $0 += 1 }
                return TaskItem.samples
            }
        } operation: { TaskBoardViewModel() }

        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        #expect(calls.value == 1)
    }

    @Test("""
        Given the API returns no tasks,
        When the board loads,
        Then the empty state is shown
        """)
    func emptyResultShowsEmpty() async {
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.fetchTasks = { [] }
        } operation: { TaskBoardViewModel() }

        sut.trigger(.onAppear)
        await sut.loadTask?.value

        #expect(sut.state.phase == .empty)
        #expect(sut.state.rows.isEmpty)
    }

    @Test("""
        Given the first load fails,
        When Retry succeeds,
        Then the error is replaced by content
        """)
    func loadErrorThenRetry() async {
        let calls = LockIsolated(0)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.fetchTasks = {
                let call = calls.withValue { $0 += 1; return $0 }
                if call == 1 { throw TestError() }
                return TaskItem.samples
            }
        } operation: { TaskBoardViewModel() }

        sut.trigger(.onAppear)
        await sut.loadTask?.value
        #expect(sut.state.phase == .failed)
        #expect(sut.state.rows.isEmpty)

        sut.trigger(.retryTapped)
        #expect(sut.state.phase == .loading)
        await sut.loadTask?.value

        #expect(sut.state.phase == .content)
        #expect(sut.state.rows.count == TaskItem.samples.count)
    }

    @Test("""
        Given loaded content,
        When a refresh fails,
        Then the previous rows stay and a reload banner is shown
        """)
    func refreshErrorRetainsContent() async {
        let calls = LockIsolated(0)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.fetchTasks = {
                let call = calls.withValue { $0 += 1; return $0 }
                if call == 2 { throw TestError() }
                return TaskItem.samples
            }
        } operation: { TaskBoardViewModel() }

        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.refreshRequested)
        await sut.loadTask?.value

        #expect(sut.state.phase == .content)
        #expect(sut.state.rows.map(\.id) == TaskItem.samples.map(\.id))
        #expect(sut.state.reloadErrorMessage == L10n.TaskBoard.reloadError)

        sut.trigger(.retryTapped)
        await sut.loadTask?.value
        #expect(sut.state.reloadErrorMessage == nil)
    }

    @Test("""
        Given a load in flight,
        When a refresh is requested,
        Then the stale first result is ignored
        """)
    func staleLoadIsIgnored() async {
        let fresh = [TaskItem(id: UUID(), title: "Fresh", priority: .low)]
        let stale = [TaskItem(id: UUID(), title: "Stale", priority: .high)]
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (gate, gateContinuation) = AsyncStream<[TaskItem]>.makeStream()
        let calls = LockIsolated(0)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.fetchTasks = {
                let call = calls.withValue { $0 += 1; return $0 }
                guard call == 1 else { return fresh }
                startedContinuation.yield()
                for await items in gate { return items }
                throw CancellationError()
            }
        } operation: { TaskBoardViewModel() }

        sut.trigger(.onAppear)
        var startedIterator = started.makeAsyncIterator()
        _ = await startedIterator.next()
        let firstLoad = sut.loadTask

        sut.trigger(.refreshRequested)
        await sut.loadTask?.value
        gateContinuation.yield(stale)
        gateContinuation.finish()
        await firstLoad?.value

        #expect(sut.state.rows.map(\.id) == fresh.map(\.id))
    }

    @Test("""
        Given a refresh is in flight,
        When a completion update succeeds before its stale result returns,
        Then the board reloads instead of reverting the confirmed update
        """)
    func refreshDoesNotRevertConcurrentCompletion() async {
        let updatedTasks = TaskItem.samples.map { item in
            guard item.id == firstID else { return item }
            var updated = item
            updated.isComplete = true
            return updated
        }
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (gate, gateContinuation) = AsyncStream<[TaskItem]>.makeStream()
        let calls = LockIsolated(0)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.fetchTasks = {
                let call = calls.withValue { $0 += 1; return $0 }
                switch call {
                case 1:
                    return TaskItem.samples
                case 2:
                    startedContinuation.yield()
                    for await items in gate { return items }
                    throw CancellationError()
                default:
                    return updatedTasks
                }
            }
            $0.taskClient.updateTask = { $0 }
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        sut.trigger(.refreshRequested)
        var startedIterator = started.makeAsyncIterator()
        _ = await startedIterator.next()
        let staleRefresh = sut.loadTask

        sut.trigger(.completionToggled(firstID))
        await sut.completionTasks[firstID]?.value
        #expect(sut.state.rows[0].isComplete)

        gateContinuation.yield(TaskItem.samples)
        gateContinuation.finish()
        await staleRefresh?.value
        await sut.loadTask?.value

        #expect(calls.value == 3)
        #expect(sut.state.rows[0].isComplete)
    }
}

@MainActor
struct TaskBoardCompletionTests {
    @Test("""
        Given loaded tasks,
        When a row's completion is toggled and the update succeeds,
        Then only that row changes and order is preserved
        """)
    func completionSuccess() async {
        let requests = LockIsolated<[TaskItem]>([])
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.updateTask = { task in
                requests.withValue { $0.append(task) }
                return task
            }
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        sut.trigger(.completionToggled(firstID))
        #expect(sut.state.rows[0].isCompletionInFlight)
        await sut.completionTasks[firstID]?.value

        #expect(requests.value.map(\.id) == [firstID])
        #expect(requests.value.first?.isComplete == true)
        #expect(sut.state.rows[0].isComplete)
        #expect(!sut.state.rows[0].isCompletionInFlight)
        #expect(sut.state.rows.map(\.id) == TaskItem.samples.map(\.id))
    }

    @Test("""
        Given a completion request in flight,
        When the row is toggled again,
        Then no second request is sent
        """)
    func completionInFlightIsDisabled() async {
        let (gate, gateContinuation) = AsyncStream<Void>.makeStream()
        let calls = LockIsolated(0)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.updateTask = { task in
                calls.withValue { $0 += 1 }
                for await _ in gate { break }
                return task
            }
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        sut.trigger(.completionToggled(firstID))
        let inFlight = sut.completionTasks[firstID]
        sut.trigger(.completionToggled(firstID))
        #expect(sut.state.rows[0].isCompletionInFlight)

        gateContinuation.yield()
        gateContinuation.finish()
        await inFlight?.value

        #expect(calls.value == 1)
        #expect(sut.state.rows[0].isComplete)
    }

    @Test("""
        Given a completion update fails,
        When Retry succeeds,
        Then the prior value is kept with an inline error, then the toggle applies
        """)
    func completionErrorThenRetry() async {
        let calls = LockIsolated(0)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.updateTask = { task in
                let call = calls.withValue { $0 += 1; return $0 }
                if call == 1 { throw TestError() }
                return task
            }
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        sut.trigger(.completionToggled(dentistID))
        await sut.completionTasks[dentistID]?.value

        #expect(sut.state.rows[2].isComplete)
        #expect(sut.state.rows[2].completionErrorMessage == L10n.TaskBoard.completionError)
        #expect(!sut.state.rows[2].isCompletionInFlight)

        sut.trigger(.completionRetryTapped(dentistID))
        await sut.completionTasks[dentistID]?.value

        #expect(!sut.state.rows[2].isComplete)
        #expect(sut.state.rows[2].completionErrorMessage == nil)
        #expect(sut.state.rows.map(\.id) == TaskItem.samples.map(\.id))
    }
}

@MainActor
struct TaskBoardAddTests {
    @Test("""
        Given loaded tasks,
        When Add is tapped,
        Then an add child is created once
        """)
    func addCreatesChild() async {
        let sut = withDependencies { makeDependencies(&$0) } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        sut.trigger(.addTapped)
        let child = sut.addViewModel
        sut.trigger(.addTapped)

        #expect(child != nil)
        #expect(sut.addViewModel === child)
    }

    @Test("""
        Given the add sheet is open,
        When the child reports a created task,
        Then it is appended and the sheet is dismissed
        """)
    func addCreatedAppends() async {
        let created = TaskItem(id: UUID(), title: "New", priority: .medium)
        let sut = withDependencies { makeDependencies(&$0) } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        sut.trigger(.addTapped)
        sut.addViewModel?.onEvent?(.created(created))

        #expect(sut.addViewModel == nil)
        #expect(sut.state.rows.map(\.id) == TaskItem.samples.map(\.id) + [created.id])
    }

    @Test("""
        Given an empty board with an add child built from host dependencies,
        When the child saves successfully,
        Then the board shows the created task
        """)
    func addChildUsesHostDependencies() async {
        let created = TaskItem(id: UUID(), title: "Created", priority: .high)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.fetchTasks = { [] }
            $0.taskClient.createTask = { _ in created }
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        #expect(sut.state.phase == .empty)

        sut.trigger(.addTapped)
        let child = sut.addViewModel
        child?.trigger(.titleChanged("Created"))
        child?.trigger(.saveTapped)
        await child?.saveTask?.value

        #expect(sut.addViewModel == nil)
        #expect(sut.state.phase == .content)
        #expect(sut.state.rows.map(\.id) == [created.id])
    }

    @Test("""
        Given the add sheet is open,
        When the child requests close or the sheet is dismissed,
        Then the child is cleared and the list is unchanged
        """)
    func addCloseDismisses() async {
        let sut = withDependencies { makeDependencies(&$0) } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        sut.trigger(.addTapped)
        sut.addViewModel?.onEvent?(.closeRequested)
        #expect(sut.addViewModel == nil)

        sut.trigger(.addTapped)
        sut.trigger(.addDismissed)
        #expect(sut.addViewModel == nil)
        #expect(sut.state.rows.map(\.id) == TaskItem.samples.map(\.id))
    }
}

@MainActor
struct TaskBoardDetailTests {
    @Test("""
        Given loaded tasks,
        When a row is tapped twice,
        Then one detail child is created and the route carries only its UUID
        """)
    func tapPushesDetailByID() async {
        let sut = withDependencies { makeDependencies(&$0) } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        sut.trigger(.taskTapped(firstID))
        let child = sut.detailViewModel
        sut.trigger(.taskTapped(dentistID))

        #expect(sut.state.navigationPath == [.detail(id: firstID)])
        #expect(child?.state.task.id == firstID)
        #expect(sut.detailViewModel === child)
    }

    @Test("""
        Given a clean detail,
        When the system pops the path,
        Then the child is cleared
        """)
    func cleanPopClearsChild() async {
        let sut = withDependencies { makeDependencies(&$0) } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.taskTapped(firstID))

        sut.trigger(.navigationPathChanged([]))

        #expect(sut.state.navigationPath.isEmpty)
        #expect(sut.detailViewModel == nil)
        #expect(!sut.state.isDiscardConfirmationPresented)
    }

    @Test("""
        Given a detail open,
        When it reports an updated task,
        Then the row is replaced in place and detail stays pushed
        """)
    func detailUpdatedReplacesRow() async {
        let sut = withDependencies { makeDependencies(&$0) } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.taskTapped(firstID))
        var updated = TaskItem.samples[0]
        updated.title = "Renamed"
        updated.priority = .low

        sut.detailViewModel?.onEvent?(.updated(updated))

        #expect(sut.state.rows[0].title == "Renamed")
        #expect(sut.state.rows[0].priority == .low)
        #expect(sut.state.rows.map(\.id) == TaskItem.samples.map(\.id))
        #expect(sut.state.navigationPath == [.detail(id: firstID)])
        #expect(sut.detailViewModel != nil)
    }

    @Test("""
        Given a detail open,
        When it reports deletion,
        Then the row is removed, the child cleared and the route popped
        """)
    func detailDeletedRemovesAndPops() async {
        let sut = withDependencies { makeDependencies(&$0) } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.taskTapped(firstID))

        sut.detailViewModel?.onEvent?(.deleted(firstID))

        #expect(!sut.state.rows.contains { $0.id == firstID })
        #expect(sut.state.rows.map(\.id) == TaskItem.samples.dropFirst().map(\.id))
        #expect(sut.state.navigationPath.isEmpty)
        #expect(sut.detailViewModel == nil)
    }

    @Test("""
        Given a dirty detail,
        When the system pops and the user cancels the confirmation,
        Then detail stays pushed with its unchanged child
        """)
    func dirtyBackCancelKeepsDetail() async {
        let sut = withDependencies { makeDependencies(&$0) } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.taskTapped(firstID))
        let child = sut.detailViewModel
        let childState = child?.state
        child?.onEvent?(.dirtyChanged(true))

        sut.trigger(.navigationPathChanged([]))
        #expect(sut.state.isDiscardConfirmationPresented)
        #expect(sut.state.navigationPath == [.detail(id: firstID)])

        sut.trigger(.discardCancelled)
        #expect(!sut.state.isDiscardConfirmationPresented)
        #expect(sut.state.navigationPath == [.detail(id: firstID)])
        #expect(sut.detailViewModel === child)
        #expect(child?.state == childState)
    }

    @Test("""
        Given a dirty detail,
        When Back is tapped and discard is confirmed,
        Then detail pops without changing the list or the child's state
        """)
    func dirtyBackDiscardPops() async {
        let updateCalls = LockIsolated(0)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.updateTask = { task in
                updateCalls.withValue { $0 += 1 }
                return task
            }
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.taskTapped(firstID))
        let child = sut.detailViewModel
        let childState = child?.state
        child?.onEvent?(.dirtyChanged(true))

        sut.trigger(.detailBackTapped)
        #expect(sut.state.isDiscardConfirmationPresented)
        sut.trigger(.discardConfirmed)

        #expect(sut.state.navigationPath.isEmpty)
        #expect(sut.detailViewModel == nil)
        #expect(!sut.state.isDiscardConfirmationPresented)
        #expect(!sut.state.isDetailDirty)
        #expect(child?.state == childState)
        #expect(updateCalls.value == 0)
        #expect(sut.state.rows.map(\.id) == TaskItem.samples.map(\.id))
    }
}

@MainActor
struct TaskBoardRefreshTests {
    @Test("""
        Given a loaded board,
        When refresh() is awaited,
        Then it returns only after the new result is in state
        """)
    func refreshAwaitsLoadResult() async {
        let fresh = [TaskItem(id: UUID(), title: "Fresh", priority: .low)]
        let calls = LockIsolated(0)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.fetchTasks = {
                calls.withValue { $0 += 1 }
                return calls.value == 1 ? TaskItem.samples : fresh
            }
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        await sut.refresh()

        #expect(sut.state.rows.map(\.id) == fresh.map(\.id))
        #expect(sut.state.phase == .content)
    }

    @Test("""
        Given a refresh in flight,
        When a completion mutation restarts the load,
        Then refresh() also waits for the restarted load
        """)
    func refreshWaitsForRestartedLoad() async {
        let serverCopy = TaskItem.samples.map { item in
            var item = item
            item.title = "Server " + item.title
            return item
        }
        let (started, startedContinuation) = AsyncStream<Int>.makeStream()
        let (staleGate, staleGateContinuation) = AsyncStream<[TaskItem]>.makeStream()
        let (restartGate, restartGateContinuation) = AsyncStream<[TaskItem]>.makeStream()
        let calls = LockIsolated(0)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.fetchTasks = {
                let call = calls.withValue { $0 += 1; return $0 }
                let gate: AsyncStream<[TaskItem]>
                switch call {
                case 1: return TaskItem.samples
                case 2: gate = staleGate
                default: gate = restartGate
                }
                startedContinuation.yield(call)
                for await items in gate { return items }
                throw CancellationError()
            }
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        let refreshing = Task {
            await sut.refresh()
            return sut.state.rows.map(\.title)
        }
        var startedIterator = started.makeAsyncIterator()
        _ = await startedIterator.next()
        sut.trigger(.completionToggled(firstID))
        await sut.completionTasks[firstID]?.value
        staleGateContinuation.yield(TaskItem.samples)
        staleGateContinuation.finish()
        #expect(await startedIterator.next() == 3)
        restartGateContinuation.yield(serverCopy)
        restartGateContinuation.finish()
        let titlesWhenRefreshReturned = await refreshing.value

        #expect(calls.value == 3)
        #expect(titlesWhenRefreshReturned == serverCopy.map(\.title))
    }
}
