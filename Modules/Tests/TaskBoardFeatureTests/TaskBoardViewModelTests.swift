@testable import AddTaskFeature
import Combine
import Dependencies
import Foundation
import L10n
import NetworkClient
import TaskClient
import TaskDetailFeature
import Testing
@testable import TaskBoardFeature

private struct TestError: Error {}

private func makeDependencies(_ dependencies: inout DependencyValues) {
    dependencies.taskClient.fetchTasks = { TaskItem.samples }
    dependencies.taskClient.cachedTasks = { [] }
    dependencies.taskClient.updateTask = { $0 }
    dependencies.taskClient.pendingSyncCounts = { AsyncStream { $0.finish() } }
    dependencies.networkMonitorClient.isOnlineUpdates = { AsyncStream { $0.finish() } }
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
        await sut.rowTasks[firstID]?.value
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
struct TaskBoardCacheTests {
    @Test("""
        Given cached tasks,
        When the board appears,
        Then the cached rows show before the fetch returns and are then replaced
        """)
    func cachedTasksShowFirst() async {
        let cached = [TaskItem(id: UUID(), title: "Cached", priority: .low)]
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (gate, gateContinuation) = AsyncStream<[TaskItem]>.makeStream()
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.cachedTasks = { cached }
            $0.taskClient.fetchTasks = {
                startedContinuation.yield()
                for await items in gate { return items }
                throw CancellationError()
            }
        } operation: { TaskBoardViewModel() }

        sut.trigger(.onAppear)
        var startedIterator = started.makeAsyncIterator()
        _ = await startedIterator.next()

        #expect(sut.state.phase == .content)
        #expect(sut.state.rows.map(\.id) == cached.map(\.id))
        #expect(sut.state.reloadErrorMessage == nil)

        gateContinuation.yield(TaskItem.samples)
        gateContinuation.finish()
        await sut.loadTask?.value

        #expect(sut.state.rows.map(\.id) == TaskItem.samples.map(\.id))
        #expect(sut.state.reloadErrorMessage == nil)
    }

    @Test("""
        Given cached tasks and an unreachable server,
        When the board appears and Retry fails again,
        Then the cached rows stay with the offline banner until a fetch succeeds
        """)
    func failedFetchKeepsCachedRowsWithOfflineBanner() async {
        let cached = [TaskItem(id: UUID(), title: "Cached", priority: .low)]
        let calls = LockIsolated(0)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.cachedTasks = { cached }
            $0.taskClient.fetchTasks = {
                let call = calls.withValue { $0 += 1; return $0 }
                guard call > 2 else { throw TestError() }
                return TaskItem.samples
            }
        } operation: { TaskBoardViewModel() }

        sut.trigger(.onAppear)
        await sut.loadTask?.value
        #expect(sut.state.phase == .content)
        #expect(sut.state.rows.map(\.id) == cached.map(\.id))
        #expect(sut.state.reloadErrorMessage == L10n.TaskBoard.offlineError)

        sut.trigger(.retryTapped)
        await sut.loadTask?.value
        #expect(sut.state.reloadErrorMessage == L10n.TaskBoard.offlineError)

        sut.trigger(.retryTapped)
        await sut.loadTask?.value
        #expect(sut.state.rows.map(\.id) == TaskItem.samples.map(\.id))
        #expect(sut.state.reloadErrorMessage == nil)
    }

    @Test("""
        Given the cache can't be read,
        When the board appears,
        Then it ignores the cache and shows the fetched tasks
        """)
    func unreadableCacheIsIgnored() async {
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.cachedTasks = { throw TestError() }
        } operation: { TaskBoardViewModel() }

        sut.trigger(.onAppear)
        await sut.loadTask?.value

        #expect(sut.state.phase == .content)
        #expect(sut.state.rows.map(\.id) == TaskItem.samples.map(\.id))
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
        #expect(sut.state.rows[0].isInFlight)
        await sut.rowTasks[firstID]?.value

        #expect(requests.value.map(\.id) == [firstID])
        #expect(requests.value.first?.isComplete == true)
        #expect(sut.state.rows[0].isComplete)
        #expect(!sut.state.rows[0].isInFlight)
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
        let inFlight = sut.rowTasks[firstID]
        sut.trigger(.completionToggled(firstID))
        #expect(sut.state.rows[0].isInFlight)

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
        await sut.rowTasks[dentistID]?.value

        #expect(sut.state.rows[2].isComplete)
        #expect(sut.state.rows[2].errorMessage == L10n.TaskBoard.completionError)
        #expect(!sut.state.rows[2].isInFlight)

        sut.trigger(.rowRetryTapped(dentistID))
        await sut.rowTasks[dentistID]?.value

        #expect(!sut.state.rows[2].isComplete)
        #expect(sut.state.rows[2].errorMessage == nil)
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

    @Test("""
        Given the initial load failed,
        When a task is created and the follow-up load succeeds,
        Then the board shows the fetched tasks without an error
        """)
    func createdAfterFailedLoadReloads() async {
        let created = TaskItem(id: UUID(), title: "New", priority: .medium)
        let calls = LockIsolated(0)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.fetchTasks = {
                let call = calls.withValue { $0 += 1; return $0 }
                guard call > 1 else { throw TestError() }
                return TaskItem.samples + [created]
            }
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        #expect(sut.state.phase == .failed)

        sut.trigger(.addTapped)
        sut.addViewModel?.onEvent?(.created(created))
        #expect(sut.state.rows.map(\.id) == [created.id])
        await sut.loadTask?.value

        #expect(calls.value == 2)
        #expect(sut.addViewModel == nil)
        #expect(sut.state.phase == .content)
        #expect(sut.state.reloadErrorMessage == nil)
        #expect(sut.state.rows.map(\.id) == TaskItem.samples.map(\.id) + [created.id])
    }

    @Test("""
        Given the initial load failed,
        When a task is created and the follow-up load fails again,
        Then the new task stays visible with the reload error banner
        """)
    func createdAfterFailedLoadShowsReloadError() async {
        let created = TaskItem(id: UUID(), title: "New", priority: .medium)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.fetchTasks = { throw TestError() }
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        sut.trigger(.addTapped)
        sut.addViewModel?.onEvent?(.created(created))
        await sut.loadTask?.value

        #expect(sut.state.phase == .content)
        #expect(sut.state.rows.map(\.id) == [created.id])
        #expect(sut.state.reloadErrorMessage == L10n.TaskBoard.reloadError)
    }

    @Test("""
        Given the initial load is still in flight,
        When a task is created,
        Then the board reloads and shows the fetched tasks
        """)
    func createdDuringInitialLoadReloads() async {
        let created = TaskItem(id: UUID(), title: "New", priority: .medium)
        let (gate, release) = AsyncStream<Void>.makeStream()
        let calls = LockIsolated(0)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.fetchTasks = {
                calls.withValue { $0 += 1 }
                for await _ in gate { break }
                return TaskItem.samples + [created]
            }
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        let firstLoad = sut.loadTask

        sut.trigger(.addTapped)
        sut.addViewModel?.onEvent?(.created(created))
        #expect(sut.loadTask != firstLoad)
        #expect(firstLoad?.isCancelled == true)
        release.yield()
        release.finish()
        await firstLoad?.value
        await sut.loadTask?.value

        // The cancelled initial load stops before reaching the network.
        #expect(calls.value == 1)
        #expect(sut.state.phase == .content)
        #expect(sut.state.reloadErrorMessage == nil)
        #expect(sut.state.rows.map(\.id) == TaskItem.samples.map(\.id) + [created.id])
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
        Given a detail open on a task whose id a reload has since replaced,
        When the detail reports an update,
        Then the board reloads and shows the server's list
        """)
    func detailUpdateForReplacedIDReloads() async {
        let fetches = LockIsolated(0)
        let serverID = UUID()
        let renamed = TaskItem(id: serverID, title: "Renamed", priority: .low)
        let lists = [TaskItem.samples, [renamed] + TaskItem.samples.dropFirst()]
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.fetchTasks = {
                fetches.withValue { $0 += 1 }
                return lists[min(fetches.value, lists.count) - 1]
            }
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.taskTapped(firstID))

        sut.detailViewModel?.onEvent?(.updated(TaskItem(id: UUID(), title: "Renamed", priority: .low)))
        await sut.loadTask?.value

        #expect(fetches.value == 2)
        #expect(sut.state.rows.map(\.id) == [serverID] + TaskItem.samples.dropFirst().map(\.id))
        #expect(sut.state.rows[0].title == "Renamed")
        #expect(sut.detailViewModel != nil)
    }

    @Test("""
        Given a detail open on a task whose id a reload has since replaced,
        When the detail reports deletion,
        Then detail pops and the board reloads the server's list
        """)
    func detailDeleteForReplacedIDReloads() async {
        let fetches = LockIsolated(0)
        let lists = [TaskItem.samples, Array(TaskItem.samples.dropFirst())]
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.fetchTasks = {
                fetches.withValue { $0 += 1 }
                return lists[min(fetches.value, lists.count) - 1]
            }
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.taskTapped(firstID))

        sut.detailViewModel?.onEvent?(.deleted(UUID()))
        await sut.loadTask?.value

        #expect(fetches.value == 2)
        #expect(sut.state.rows.map(\.id) == TaskItem.samples.dropFirst().map(\.id))
        #expect(sut.state.navigationPath.isEmpty)
        #expect(sut.detailViewModel == nil)
    }

    @Test("""
        Given a detail open on a task whose id a reload has since replaced, and no connection,
        When the detail reports deletion and the reload fails,
        Then the board shows the cached list without the task and the offline banner
        """)
    func detailDeleteForReplacedIDOfflineShowsCache() async {
        let fetches = LockIsolated(0)
        let cached = Array(TaskItem.samples.dropFirst())
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.fetchTasks = {
                let count = fetches.withValue { $0 += 1; return $0 }
                guard count == 1 else { throw TestError() }
                return TaskItem.samples
            }
            $0.taskClient.cachedTasks = { cached }
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.taskTapped(firstID))

        sut.detailViewModel?.onEvent?(.deleted(UUID()))
        await sut.loadTask?.value

        #expect(fetches.value == 2)
        #expect(sut.state.rows.map(\.id) == cached.map(\.id))
        #expect(sut.state.reloadErrorMessage == L10n.TaskBoard.offlineError)
        #expect(sut.state.navigationPath.isEmpty)
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
        Given the discard alert is shown or was closed by Discard or Cancel,
        When the bindings report the same pop or dismissal again,
        Then the view model publishes no further change
        """)
    func repeatedDiscardCancelDoesNotPublish() async {
        let sut = withDependencies { makeDependencies(&$0) } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        var changes = 0
        let cancellable = sut.objectWillChange.sink { changes += 1 }

        sut.trigger(.taskTapped(firstID))
        sut.detailViewModel?.onEvent?(.dirtyChanged(true))
        sut.trigger(.detailBackTapped)
        changes = 0
        sut.trigger(.navigationPathChanged([]))
        #expect(changes == 0)
        sut.trigger(.discardCancelled)
        changes = 0
        sut.trigger(.discardCancelled)
        #expect(changes == 0)

        sut.trigger(.detailBackTapped)
        sut.trigger(.discardConfirmed)
        changes = 0
        sut.trigger(.discardCancelled)
        #expect(changes == 0)
        #expect(sut.state.navigationPath.isEmpty)
        cancellable.cancel()
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
        await sut.rowTasks[firstID]?.value
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

@MainActor
struct TaskBoardSwipeDeleteTests {
    private let clock = TestClock()
    private let deleteCalls = LockIsolated<[UUID]>([])

    private func swipeDependencies(
        _ dependencies: inout DependencyValues,
        fetch: @escaping @Sendable () async throws -> [TaskItem] = { TaskItem.samples },
        delete: (@Sendable (UUID) async throws -> Void)? = nil
    ) {
        let deleteCalls = deleteCalls
        makeDependencies(&dependencies)
        dependencies.continuousClock = clock
        dependencies.taskClient.fetchTasks = fetch
        dependencies.taskClient.deleteTask = { id in
            deleteCalls.withValue { $0.append(id) }
            try await delete?(id)
        }
    }

    @Test("""
        Given loaded tasks,
        When a row is swiped to delete,
        Then it is hidden, the undo banner names it and no request is sent yet
        """)
    func swipeHidesRowAndShowsUndo() async {
        let sut = withDependencies {
            swipeDependencies(&$0)
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        sut.trigger(.deleteSwiped(firstID))

        #expect(sut.state.rows.map(\.id) == TaskItem.samples.dropFirst().map(\.id))
        #expect(sut.state.undo == TaskBoardUndoState(
            message: L10n.TaskBoard.deletedMessage(TaskItem.samples[0].title)
        ))
        await clock.advance(by: .seconds(3))
        #expect(deleteCalls.value.isEmpty)
    }

    @Test("""
        Given a swiped row,
        When Undo is tapped within the window,
        Then the row returns to its position and no delete is ever sent
        """)
    func undoRestoresWithoutRequest() async {
        let sut = withDependencies {
            swipeDependencies(&$0)
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.deleteSwiped(dentistID))
        let undoTask = sut.undoTask

        sut.trigger(.undoTapped)
        await clock.advance(by: TaskBoardViewModel.undoWindow)
        await undoTask?.value

        #expect(sut.state.rows.map(\.id) == TaskItem.samples.map(\.id))
        #expect(sut.state.undo == nil)
        #expect(deleteCalls.value.isEmpty)
    }

    @Test("""
        Given a swiped row,
        When the undo window expires,
        Then the delete is sent once and the row stays removed
        """)
    func expiryCommitsDelete() async {
        let sut = withDependencies {
            swipeDependencies(&$0)
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.deleteSwiped(firstID))
        let undoTask = sut.undoTask

        await clock.advance(by: TaskBoardViewModel.undoWindow)
        await undoTask?.value
        await sut.rowTasks[firstID]?.value

        #expect(deleteCalls.value == [firstID])
        #expect(sut.state.undo == nil)
        #expect(!sut.state.rows.map(\.id).contains(firstID))
    }

    @Test("""
        Given the committed delete fails,
        When the failure arrives and Retry is tapped,
        Then the row is restored in place with an error, and Retry deletes it
        """)
    func failureRestoresRowAndRetryDeletes() async {
        let attempts = LockIsolated(0)
        let sut = withDependencies {
            swipeDependencies(&$0, delete: { _ in
                let attempt = attempts.withValue { $0 += 1; return $0 }
                if attempt == 1 { throw TestError() }
            })
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.deleteSwiped(firstID))
        let undoTask = sut.undoTask
        await clock.advance(by: TaskBoardViewModel.undoWindow)
        await undoTask?.value
        await sut.rowTasks[firstID]?.value

        #expect(sut.state.rows.map(\.id) == TaskItem.samples.map(\.id))
        #expect(sut.state.rows[0].errorMessage == L10n.TaskBoard.deleteError)

        sut.trigger(.rowRetryTapped(firstID))
        #expect(sut.state.rows[0].isInFlight)
        await sut.rowTasks[firstID]?.value

        #expect(deleteCalls.value == [firstID, firstID])
        #expect(sut.state.rows.map(\.id) == TaskItem.samples.dropFirst().map(\.id))
    }

    @Test("""
        Given a pending swiped row,
        When another row is swiped,
        Then the first delete is sent immediately and Undo applies only to the second
        """)
    func secondSwipeCommitsFirst() async {
        let sut = withDependencies {
            swipeDependencies(&$0)
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.deleteSwiped(firstID))

        sut.trigger(.deleteSwiped(dentistID))
        await sut.rowTasks[firstID]?.value
        #expect(deleteCalls.value == [firstID])
        #expect(sut.state.undo?.message == L10n.TaskBoard.deletedMessage(TaskItem.samples[2].title))

        sut.trigger(.undoTapped)
        #expect(sut.state.rows.map(\.id) == TaskItem.samples.dropFirst().map(\.id))
    }

    @Test("""
        Given a pending swiped row,
        When the list reloads,
        Then the row stays hidden and Undo still restores it in place
        """)
    func reloadKeepsPendingRowHidden() async {
        let sut = withDependencies {
            swipeDependencies(&$0)
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.deleteSwiped(firstID))

        await sut.refresh()
        #expect(!sut.state.rows.map(\.id).contains(firstID))

        sut.trigger(.undoTapped)
        #expect(sut.state.rows.map(\.id) == TaskItem.samples.map(\.id))
    }

    @Test("""
        Given a single task,
        When it is swiped and then undone,
        Then the board shows empty and then content again
        """)
    func swipingLastRowShowsEmptyUntilUndo() async {
        let only = TaskItem.samples[0]
        let sut = withDependencies {
            swipeDependencies(&$0, fetch: { [only] })
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        sut.trigger(.deleteSwiped(only.id))
        #expect(sut.state.phase == .empty)
        #expect(sut.state.undo != nil)

        sut.trigger(.undoTapped)
        #expect(sut.state.phase == .content)
        #expect(sut.state.rows.map(\.id) == [only.id])
    }

    @Test("""
        Given a completion request in flight,
        When the same row is swiped,
        Then the swipe is ignored
        """)
    func swipeIgnoredWhileRowInFlight() async {
        let (gate, gateContinuation) = AsyncStream<Void>.makeStream()
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.continuousClock = clock
            $0.locale = Locale(identifier: "en_US")
            $0.taskClient.updateTask = { item in
                for await _ in gate { break }
                return item
            }
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.completionToggled(firstID))

        sut.trigger(.deleteSwiped(firstID))

        #expect(sut.state.undo == nil)
        #expect(sut.state.rows.map(\.id) == TaskItem.samples.map(\.id))
        gateContinuation.finish()
        await sut.rowTasks[firstID]?.value
    }
}

@MainActor
struct TaskBoardSearchSortTests {
    private static func item(_ title: String, _ priority: TaskPriority, done: Bool = false) -> TaskItem {
        TaskItem(id: UUID(), title: title, priority: priority, isComplete: done)
    }

    private let items = [
        item("Low A", .low),
        item("High A", .high, done: true),
        item("Medium A", .medium),
        item("High B", .high),
        item("Crème brûlée", .low, done: true),
        item("Medium B", .medium, done: true),
    ]

    private func searchDependencies(_ dependencies: inout DependencyValues, items: [TaskItem]? = nil) {
        let items = items ?? self.items
        makeDependencies(&dependencies)
        dependencies.taskClient.fetchTasks = { items }
    }

    private func titles(_ sut: TaskBoardViewModel) -> [String] {
        sut.state.rows.map(\.title)
    }

    @Test("""
        Given loaded tasks,
        When Priority sort is chosen,
        Then rows go High → Low and ties keep API order
        """)
    func sortByPriorityIsStable() async {
        let sut = withDependencies {
            searchDependencies(&$0)
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        sut.trigger(.sortChanged(.priority))

        #expect(sut.state.sortOrder == .priority)
        #expect(titles(sut) == ["High A", "High B", "Medium A", "Medium B", "Low A", "Crème brûlée"])
    }

    @Test("""
        Given loaded tasks,
        When Status sort is chosen and then Default,
        Then incomplete rows come first in API order, and Default restores API order
        """)
    func sortByStatusThenDefault() async {
        let sut = withDependencies {
            searchDependencies(&$0)
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        sut.trigger(.sortChanged(.status))
        #expect(titles(sut) == ["Low A", "Medium A", "High B", "High A", "Crème brûlée", "Medium B"])

        sut.trigger(.sortChanged(.default))
        #expect(titles(sut) == items.map(\.title))
    }

    @Test("""
        Given loaded tasks,
        When the search text differs in case, diacritics and surrounding spaces,
        Then matching titles are still found
        """)
    func searchIgnoresCaseDiacriticsAndWhitespace() async {
        let sut = withDependencies {
            searchDependencies(&$0)
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        sut.trigger(.searchTextChanged("  CREME  "))
        #expect(titles(sut) == ["Crème brûlée"])

        sut.trigger(.searchTextChanged("   "))
        #expect(titles(sut) == items.map(\.title))
        #expect(!sut.state.isNoResults)
    }

    @Test("""
        Given a search and a sort,
        When both apply,
        Then the filtered rows keep the sort order
        """)
    func searchAndSortCombine() async {
        let sut = withDependencies {
            searchDependencies(&$0)
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        sut.trigger(.sortChanged(.priority))
        sut.trigger(.searchTextChanged("b"))

        #expect(titles(sut) == ["High B", "Medium B", "Crème brûlée"])
    }

    @Test("""
        Given loaded tasks,
        When nothing matches the search,
        Then the board stays in content with the no-results flag, not empty
        """)
    func noResultsDiffersFromEmpty() async {
        let sut = withDependencies {
            searchDependencies(&$0)
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        sut.trigger(.searchTextChanged("zzz"))

        #expect(sut.state.phase == .content)
        #expect(sut.state.rows.isEmpty)
        #expect(sut.state.isNoResults)

        let empty = withDependencies {
            searchDependencies(&$0, items: [])
        } operation: { TaskBoardViewModel() }
        empty.trigger(.onAppear)
        await empty.loadTask?.value
        empty.trigger(.searchTextChanged("zzz"))
        #expect(empty.state.phase == .empty)
        #expect(!empty.state.isNoResults)
    }

    @Test("""
        Given an active Status sort and search,
        When a completion toggle succeeds,
        Then the row moves to its sorted position and search still applies
        """)
    func completionReordersUnderStatusSort() async {
        let sut = withDependencies {
            searchDependencies(&$0)
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.sortChanged(.status))
        sut.trigger(.searchTextChanged("a"))
        let lowA = items[0].id

        sut.trigger(.completionToggled(lowA))
        await sut.rowTasks[lowA]?.value

        #expect(titles(sut) == ["Medium A", "Low A", "High A"])
    }

    @Test("""
        Given an active search,
        When a new task is created from the Add sheet,
        Then it appears only if it matches the search
        """)
    func createdTaskRespectsSearch() async {
        let sut = withDependencies {
            searchDependencies(&$0)
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.searchTextChanged("high"))
        sut.trigger(.addTapped)

        sut.addViewModel?.onEvent?(.created(Self.item("Buy milk", .high)))
        #expect(titles(sut) == ["High A", "High B"])

        sut.trigger(.addTapped)
        sut.addViewModel?.onEvent?(.created(Self.item("High C", .low)))
        #expect(titles(sut) == ["High A", "High B", "High C"])
    }

    @Test("""
        Given an active search,
        When a matching row is swiped and undone,
        Then it returns to the same filtered position
        """)
    func swipeUndoUnderSearch() async {
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.continuousClock = TestClock()
            $0.taskClient.fetchTasks = { [items] in items }
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.searchTextChanged("high"))

        sut.trigger(.deleteSwiped(items[1].id))
        #expect(titles(sut) == ["High B"])

        sut.trigger(.undoTapped)
        #expect(titles(sut) == ["High A", "High B"])
    }
}

@MainActor
struct TaskBoardDueDateTests {
    private static func utcDay(_ day: String) -> Date {
        try! Date("\(day)T00:00:00Z", strategy: .iso8601)
    }

    private static func item(_ title: String, due: String?, done: Bool = false) -> TaskItem {
        TaskItem(id: UUID(), title: title, priority: .medium, isComplete: done, dueDate: due.map(utcDay))
    }

    private func dueDateDependencies(_ dependencies: inout DependencyValues, _ items: [TaskItem]) {
        makeDependencies(&dependencies)
        // 2025-03-10 23:30 in Los Angeles: local today is 2025-03-10 although UTC is already the 11th.
        dependencies.date.now = try! Date("2025-03-11T06:30:00Z", strategy: .iso8601)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        dependencies.calendar = calendar
        dependencies.locale = Locale(identifier: "en_US")
        dependencies.taskClient.fetchTasks = { items }
    }

    @Test("""
        Given incomplete tasks due around the local today,
        When the board loads,
        Then rows show relative due text and only past ones are overdue
        """)
    func relativeTextForIncompleteTasks() async {
        let sut = withDependencies {
            dueDateDependencies(&$0, [
                Self.item("none", due: nil),
                Self.item("today", due: "2025-03-10"),
                Self.item("tomorrow", due: "2025-03-11"),
                Self.item("in3", due: "2025-03-13"),
                Self.item("yesterday", due: "2025-03-09"),
                Self.item("ago2", due: "2025-03-08"),
            ])
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        #expect(sut.state.rows.map(\.dueText) == [
            nil,
            "Due today",
            "Due tomorrow",
            "Due in 3 days",
            "Overdue by 1 day",
            "Overdue by 2 days",
        ])
        #expect(sut.state.rows.map(\.isOverdue) == [false, false, false, false, true, true])
    }

    @Test("""
        Given completed tasks with past due dates,
        When the board loads,
        Then rows show plain past due text without overdue styling
        """)
    func completedTasksAreNeverOverdue() async {
        let sut = withDependencies {
            dueDateDependencies(&$0, [
                Self.item("yesterday", due: "2025-03-09", done: true),
                Self.item("ago5", due: "2025-03-05", done: true),
                Self.item("today", due: "2025-03-10", done: true),
            ])
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        #expect(sut.state.rows.map(\.dueText) == ["Due yesterday", "Due 5 days ago", "Due today"])
        #expect(sut.state.rows.allSatisfy { !$0.isOverdue })
    }

    @Test("""
        Given an overdue task,
        When its completion toggle succeeds,
        Then the row is no longer overdue
        """)
    func completingClearsOverdue() async {
        let overdue = Self.item("late", due: "2025-03-01")
        let sut = withDependencies {
            dueDateDependencies(&$0, [overdue])
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        #expect(sut.state.rows[0].isOverdue)

        sut.trigger(.completionToggled(overdue.id))
        await sut.rowTasks[overdue.id]?.value

        #expect(!sut.state.rows[0].isOverdue)
        #expect(sut.state.rows[0].dueText == "Due 9 days ago")
    }
}

@MainActor
struct TaskBoardReviewFixTests {
    @Test("""
        Given a completion request in flight,
        When the row is tapped,
        Then detail does not open on the stale task
        """)
    func detailBlockedWhileRowInFlight() async {
        let (gate, gateContinuation) = AsyncStream<Void>.makeStream()
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.updateTask = { item in
                for await _ in gate { break }
                return item
            }
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.completionToggled(firstID))

        sut.trigger(.taskTapped(firstID))

        #expect(sut.detailViewModel == nil)
        #expect(sut.state.navigationPath.isEmpty)
        gateContinuation.finish()
        await sut.rowTasks[firstID]?.value
        sut.trigger(.taskTapped(firstID))
        #expect(sut.detailViewModel != nil)
    }

    @Test("""
        Given detail is open for a row whose swipe delete failed,
        When the row delete is retried and succeeds,
        Then detail is popped
        """)
    func successfulRowDeletePopsItsDetail() async {
        let clock = TestClock()
        let attempts = LockIsolated(0)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.continuousClock = clock
            $0.locale = Locale(identifier: "en_US")
            $0.taskClient.deleteTask = { _ in
                let attempt = attempts.withValue { $0 += 1; return $0 }
                if attempt == 1 { throw TestError() }
            }
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.deleteSwiped(firstID))
        let undoTask = sut.undoTask
        await clock.advance(by: TaskBoardViewModel.undoWindow)
        await undoTask?.value
        await sut.rowTasks[firstID]?.value
        sut.trigger(.taskTapped(firstID))
        #expect(sut.detailViewModel != nil)

        sut.trigger(.rowRetryTapped(firstID))
        await sut.rowTasks[firstID]?.value

        #expect(sut.detailViewModel == nil)
        #expect(sut.state.navigationPath.isEmpty)
        #expect(!sut.state.rows.map(\.id).contains(firstID))
    }

    @Test("""
        Given a task due tomorrow,
        When the day rolls over and the scene reports it,
        Then the row reads "Due today"
        """)
    func dayChangeRecomputesDueText() async {
        let now = LockIsolated(try! Date("2025-03-10T12:00:00Z", strategy: .iso8601))
        let task = TaskItem(
            id: UUID(), title: "T", priority: .low,
            dueDate: try! Date("2025-03-11T00:00:00Z", strategy: .iso8601)
        )
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.date = DateGenerator { now.value }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            $0.calendar = calendar
            $0.locale = Locale(identifier: "en_US")
            $0.taskClient.fetchTasks = { [task] }
        } operation: { TaskBoardViewModel() }
        sut.trigger(.onAppear)
        await sut.loadTask?.value
        #expect(sut.state.rows[0].dueText == "Due tomorrow")

        now.setValue(try! Date("2025-03-11T08:00:00Z", strategy: .iso8601))
        sut.trigger(.dayMayHaveChanged)

        #expect(sut.state.rows[0].dueText == "Due today")
    }
}

@MainActor
struct TaskBoardSyncTests {
    @Test("""
        Given a fetched task with a change not synced yet,
        When the board loads,
        Then only that row has the pending-sync badge
        """)
    func pendingTaskShowsBadge() async {
        var pending = TaskItem.samples
        pending[1].isPendingSync = true
        let tasks = pending
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.fetchTasks = { tasks }
        } operation: { TaskBoardViewModel() }

        sut.trigger(.onAppear)
        await sut.loadTask?.value

        #expect(sut.state.rows.map(\.pendingSyncLabel) == [nil, L10n.TaskBoard.pendingSyncRow, nil, nil])
    }

    @Test("""
        Given changes waiting to sync,
        When the count is reported and later drops to zero,
        Then the banner shows the count and then hides
        """)
    func pendingCountDrivesBanner() async {
        let locale = Locale(identifier: "en_US")
        let (counts, continuation) = AsyncStream<Int>.makeStream()
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.locale = locale
            $0.continuousClock = TestClock()
            $0.taskClient.pendingSyncCounts = { counts }
        } operation: { TaskBoardViewModel() }

        sut.trigger(.onAppear)
        continuation.yield(2)
        continuation.finish()
        await sut.pendingSyncTask?.value
        #expect(sut.state.pendingSyncMessage == L10n.TaskBoard.pendingSyncCount(2, locale: locale))
        #expect(sut.state.pendingSyncMessage == "2 changes waiting to sync")

        let (zero, zeroContinuation) = AsyncStream<Int>.makeStream()
        let cleared = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.pendingSyncCounts = { zero }
        } operation: { TaskBoardViewModel(state: TaskBoardViewState(pendingSyncMessage: "stale")) }
        cleared.trigger(.onAppear)
        zeroContinuation.yield(0)
        zeroContinuation.finish()
        await cleared.pendingSyncTask?.value
        #expect(cleared.state.pendingSyncMessage == nil)
    }

    @Test("""
        Given a loaded board,
        When the network path goes from online to offline and back,
        Then it reloads once, on getting the connection back
        """)
    func reconnectReloads() async {
        let fetches = LockIsolated(0)
        let (paths, continuation) = AsyncStream<Bool>.makeStream()
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.taskClient.fetchTasks = {
                fetches.withValue { $0 += 1 }
                return TaskItem.samples
            }
            $0.networkMonitorClient.isOnlineUpdates = { paths }
        } operation: { TaskBoardViewModel() }

        sut.trigger(.onAppear)
        await sut.loadTask?.value
        continuation.yield(true)
        continuation.yield(true)
        continuation.yield(false)
        continuation.yield(true)
        continuation.finish()
        await sut.connectivityTask?.value
        await sut.loadTask?.value

        #expect(fetches.value == 2)
        #expect(sut.state.phase == .content)
    }

    @Test("""
        Given changes that fail to sync,
        When the backoff delays pass,
        Then the board retries after 5 s and then after 10 s more
        """)
    func pendingChangesRetryWithBackoff() async {
        let clock = TestClock()
        let fetches = LockIsolated(0)
        let (counts, continuation) = AsyncStream<Int>.makeStream()
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.continuousClock = clock
            $0.locale = Locale(identifier: "en_US")
            $0.taskClient.fetchTasks = {
                fetches.withValue { $0 += 1 }
                return TaskItem.samples
            }
            $0.taskClient.pendingSyncCounts = { counts }
        } operation: { TaskBoardViewModel() }

        sut.trigger(.onAppear)
        await sut.loadTask?.value
        continuation.yield(1)
        continuation.finish()
        await sut.pendingSyncTask?.value

        await clock.advance(by: .seconds(4))
        #expect(fetches.value == 1)
        var retry = sut.syncRetryTask
        await clock.advance(by: .seconds(1))
        await retry?.value
        await sut.loadTask?.value
        #expect(fetches.value == 2)

        retry = sut.syncRetryTask
        await clock.advance(by: .seconds(9))
        #expect(fetches.value == 2)
        await clock.advance(by: .seconds(1))
        await retry?.value
        await sut.loadTask?.value
        #expect(fetches.value == 3)
    }

    @Test("""
        Given a scheduled sync retry,
        When the pending count drops to zero,
        Then the retry is cancelled and no extra reload happens
        """)
    func syncedChangesCancelRetry() async {
        let clock = TestClock()
        let fetches = LockIsolated(0)
        let (counts, continuation) = AsyncStream<Int>.makeStream()
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.continuousClock = clock
            $0.locale = Locale(identifier: "en_US")
            $0.taskClient.fetchTasks = {
                fetches.withValue { $0 += 1 }
                return TaskItem.samples
            }
            $0.taskClient.pendingSyncCounts = { counts }
        } operation: { TaskBoardViewModel() }

        sut.trigger(.onAppear)
        await sut.loadTask?.value
        continuation.yield(1)
        continuation.yield(0)
        continuation.finish()
        await sut.pendingSyncTask?.value
        #expect(sut.syncRetryTask == nil)

        await clock.advance(by: .seconds(300))
        #expect(fetches.value == 1)
    }

    @Test("""
        Given changes waiting to sync,
        When the device is offline,
        Then no retry is scheduled until the connection is back
        """)
    func offlineSkipsSyncRetry() async {
        let clock = TestClock()
        let fetches = LockIsolated(0)
        let (counts, countContinuation) = AsyncStream<Int>.makeStream()
        let (paths, pathContinuation) = AsyncStream<Bool>.makeStream()
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.continuousClock = clock
            $0.locale = Locale(identifier: "en_US")
            $0.taskClient.fetchTasks = {
                fetches.withValue { $0 += 1 }
                return TaskItem.samples
            }
            $0.taskClient.pendingSyncCounts = { counts }
            $0.networkMonitorClient.isOnlineUpdates = { paths }
        } operation: { TaskBoardViewModel() }

        sut.trigger(.onAppear)
        await sut.loadTask?.value
        pathContinuation.yield(false)
        pathContinuation.finish()
        await sut.connectivityTask?.value
        countContinuation.yield(1)
        countContinuation.finish()
        await sut.pendingSyncTask?.value

        #expect(sut.syncRetryTask == nil)
        await clock.advance(by: .seconds(300))
        #expect(fetches.value == 1)
    }

    @Test("""
        Given the retry delay schedule,
        When attempts grow,
        Then delays double from 5 s and stop at 5 min
        """)
    func syncRetryDelayDoublesUpToCap() {
        let delays = (0..<8).map { TaskBoardViewModel.syncRetryDelay(attempt: $0) }
        #expect(delays == [5, 10, 20, 40, 80, 160, 300, 300].map { Duration.seconds($0) })
    }

    @Test("""
        Given cached tasks with the offline banner and a change waiting to sync,
        When the retry fires and its fetch fails again,
        Then the list and banner stay put during the retry and another retry is scheduled
        """)
    func failedRetryKeepsBannerAndReschedules() async {
        let clock = TestClock()
        let fetches = LockIsolated(0)
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (gate, gateContinuation) = AsyncStream<Void>.makeStream()
        let (counts, continuation) = AsyncStream<Int>.makeStream()
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.continuousClock = clock
            $0.locale = Locale(identifier: "en_US")
            $0.taskClient.cachedTasks = { TaskItem.samples }
            $0.taskClient.fetchTasks = {
                let count = fetches.withValue { $0 += 1; return $0 }
                if count > 1 {
                    startedContinuation.yield()
                    for await _ in gate { break }
                }
                throw TestError()
            }
            $0.taskClient.pendingSyncCounts = { counts }
        } operation: { TaskBoardViewModel() }

        sut.trigger(.onAppear)
        await sut.loadTask?.value
        continuation.yield(1)
        continuation.finish()
        await sut.pendingSyncTask?.value
        #expect(sut.state.reloadErrorMessage == L10n.TaskBoard.offlineError)

        let retry = sut.syncRetryTask
        await clock.advance(by: .seconds(5))
        await retry?.value
        var startedIterator = started.makeAsyncIterator()
        await startedIterator.next()
        #expect(sut.state.phase == .content)
        #expect(sut.state.reloadErrorMessage == L10n.TaskBoard.offlineError)

        gateContinuation.yield()
        await sut.loadTask?.value
        #expect(fetches.value == 2)
        #expect(sut.state.reloadErrorMessage == L10n.TaskBoard.offlineError)
        #expect(sut.syncRetryTask != nil)
    }

    @Test("""
        Given a scheduled sync retry and a pull-to-refresh still loading,
        When the retry comes due,
        Then it leaves the running load alone
        """)
    func retryDoesNotCancelRunningLoad() async {
        let clock = TestClock()
        let fetches = LockIsolated(0)
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (gate, gateContinuation) = AsyncStream<Void>.makeStream()
        let (counts, continuation) = AsyncStream<Int>.makeStream()
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.continuousClock = clock
            $0.locale = Locale(identifier: "en_US")
            $0.taskClient.fetchTasks = {
                let count = fetches.withValue { $0 += 1; return $0 }
                if count == 2 {
                    startedContinuation.yield()
                    for await _ in gate { break }
                }
                return TaskItem.samples
            }
            $0.taskClient.pendingSyncCounts = { counts }
        } operation: { TaskBoardViewModel() }

        sut.trigger(.onAppear)
        await sut.loadTask?.value
        continuation.yield(1)
        continuation.finish()
        await sut.pendingSyncTask?.value
        let retry = sut.syncRetryTask

        sut.trigger(.refreshRequested)
        let running = sut.loadTask
        var startedIterator = started.makeAsyncIterator()
        await startedIterator.next()
        await clock.advance(by: .seconds(5))
        await retry?.value
        #expect(sut.loadTask == running)
        #expect(running?.isCancelled == false)

        gateContinuation.yield()
        await sut.loadTask?.value
        #expect(fetches.value == 2)
        #expect(sut.syncRetryTask != nil)
    }

    @Test("""
        Given a scheduled sync retry,
        When the device goes offline,
        Then the retry is cancelled
        """)
    func goingOfflineCancelsRetry() async {
        let clock = TestClock()
        let fetches = LockIsolated(0)
        let (counts, countContinuation) = AsyncStream<Int>.makeStream()
        let (paths, pathContinuation) = AsyncStream<Bool>.makeStream()
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.continuousClock = clock
            $0.locale = Locale(identifier: "en_US")
            $0.taskClient.fetchTasks = {
                fetches.withValue { $0 += 1 }
                return TaskItem.samples
            }
            $0.taskClient.pendingSyncCounts = { counts }
            $0.networkMonitorClient.isOnlineUpdates = { paths }
        } operation: { TaskBoardViewModel() }

        sut.trigger(.onAppear)
        await sut.loadTask?.value
        countContinuation.yield(1)
        countContinuation.finish()
        await sut.pendingSyncTask?.value
        #expect(sut.syncRetryTask != nil)

        pathContinuation.yield(false)
        pathContinuation.finish()
        await sut.connectivityTask?.value
        #expect(sut.syncRetryTask == nil)
        await clock.advance(by: .seconds(300))
        #expect(fetches.value == 1)
    }

    @Test("""
        Given a retry already scheduled once,
        When the connection comes back after being lost,
        Then the next retry is again 5 s away
        """)
    func reconnectResetsBackoff() async {
        let clock = TestClock()
        let fetches = LockIsolated(0)
        let (counts, countContinuation) = AsyncStream<Int>.makeStream()
        let (paths, pathContinuation) = AsyncStream<Bool>.makeStream()
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.continuousClock = clock
            $0.locale = Locale(identifier: "en_US")
            $0.taskClient.fetchTasks = {
                fetches.withValue { $0 += 1 }
                return TaskItem.samples
            }
            $0.taskClient.pendingSyncCounts = { counts }
            $0.networkMonitorClient.isOnlineUpdates = { paths }
        } operation: { TaskBoardViewModel() }

        sut.trigger(.onAppear)
        await sut.loadTask?.value
        countContinuation.yield(1)
        countContinuation.finish()
        await sut.pendingSyncTask?.value
        pathContinuation.yield(false)
        pathContinuation.yield(true)
        pathContinuation.finish()
        await sut.connectivityTask?.value
        await sut.loadTask?.value
        #expect(fetches.value == 2)

        let retry = sut.syncRetryTask
        await clock.advance(by: .seconds(5))
        await retry?.value
        await sut.loadTask?.value
        #expect(fetches.value == 3)
    }

    @Test("""
        Given a retry already scheduled once,
        When the queue empties and a new change starts waiting,
        Then the next retry is again 5 s away
        """)
    func emptyQueueResetsBackoff() async {
        let clock = TestClock()
        let fetches = LockIsolated(0)
        let (counts, continuation) = AsyncStream<Int>.makeStream()
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.continuousClock = clock
            $0.locale = Locale(identifier: "en_US")
            $0.taskClient.fetchTasks = {
                fetches.withValue { $0 += 1 }
                return TaskItem.samples
            }
            $0.taskClient.pendingSyncCounts = { counts }
        } operation: { TaskBoardViewModel() }

        sut.trigger(.onAppear)
        await sut.loadTask?.value
        continuation.yield(1)
        continuation.yield(0)
        continuation.yield(1)
        continuation.finish()
        await sut.pendingSyncTask?.value

        let retry = sut.syncRetryTask
        await clock.advance(by: .seconds(5))
        await retry?.value
        await sut.loadTask?.value
        #expect(fetches.value == 2)
    }
}
