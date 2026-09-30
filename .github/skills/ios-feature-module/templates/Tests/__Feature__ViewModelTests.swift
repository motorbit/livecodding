import Dependencies
import Logging
import Testing
// >>> effect
import __Client__
// <<< effect
@testable import __Feature__Feature

@MainActor
struct __Feature__ViewModelTests {
    @Test("""
        Given a view model,
        When close is tapped,
        Then it emits closeRequested once
        """)
    func closeTappedEmitsCloseRequested() {
        let sut = withDependencies {
            makeDependencies(&$0)
        } operation: {
            __Feature__ViewModel()
        }
        var events: [__Feature__ViewModelEvent] = []
        sut.onEvent = { events.append($0) }

        sut.trigger(.closeTapped)

        #expect(events == [.closeRequested])
    }

    // >>> effect
    @Test("""
        Given the client returns content,
        When the view appears,
        Then loading is shown and then the content replaces it
        """)
    func onAppearLoadsContent() async {
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.__client__.load = { "Hello" }
        } operation: {
            __Feature__ViewModel()
        }

        sut.trigger(.onAppear)
        #expect(sut.state.isLoading)

        await sut.loadTask?.value  // deterministic: await the stored task, never sleep

        #expect(sut.state.isLoading == false)
        #expect(sut.state.content == "Hello")
        #expect(sut.state.errorMessage == nil)
    }

    @Test("""
        Given the client fails,
        When the view appears,
        Then an error message is shown and the error is logged
        """)
    func onAppearFailureShowsError() async {
        struct Failure: Error {}
        let loggedErrors = LockIsolated(0)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.__client__.load = { throw Failure() }
            $0.logger.logError = { _, _ in loggedErrors.withValue { $0 += 1 } }
        } operation: {
            __Feature__ViewModel()
        }

        sut.trigger(.onAppear)
        await sut.loadTask?.value

        #expect(sut.state.errorMessage != nil)
        #expect(sut.state.content == nil)
        #expect(loggedErrors.value == 1)
    }

    @Test("""
        Given a first load is still in flight,
        When the user retries and the first load finishes last,
        Then only the latest result is applied
        """)
    func staleResultIsDropped() async {
        // Suspending stub: the first call waits on a gate that ignores cancellation, so its
        // result really arrives after the second call. Removing the generation/cancel guard in
        // the VM makes this test fail.
        let (gate, openGate) = AsyncStream<Void>.makeStream()
        let gateTask = Task { for await _ in gate {} }
        let calls = LockIsolated(0)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.__client__.load = {
                let call = calls.withValue { $0 += 1; return $0 }
                if call == 1 {
                    await gateTask.value
                    return "stale"
                }
                return "fresh"
            }
        } operation: {
            __Feature__ViewModel()
        }

        sut.trigger(.onAppear)
        let firstTask = sut.loadTask
        sut.trigger(.retryTapped)
        await sut.loadTask?.value
        openGate.finish()
        await firstTask?.value

        #expect(calls.value == 2)
        #expect(sut.state.content == "fresh")
    }

    @Test("""
        Given content is already loaded,
        When the view appears again,
        Then the client is not called again
        """)
    func onAppearDoesNotReloadLoadedContent() async {
        let calls = LockIsolated(0)
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.__client__.load = { calls.withValue { $0 += 1 }; return "Hello" }
        } operation: {
            __Feature__ViewModel()
        }

        sut.trigger(.onAppear)
        await sut.loadTask?.value
        sut.trigger(.onAppear)
        await sut.loadTask?.value

        #expect(calls.value == 1)
    }
    // <<< effect
}

/// Safe shared defaults for this suite. Each test overrides only what it asserts on. Endpoints
/// that aren't stubbed stay unimplemented and fail the test if they're called.
private func makeDependencies(_ dependencies: inout DependencyValues) {
    dependencies.logger.log = { _, _, _ in }
    dependencies.logger.logError = { _, _ in }
}
