import Dependencies
import Logging
import Testing
@testable import BootstrapFeature

@MainActor
struct BootstrapViewModelTests {
    @Test("""
        Given a bootstrap view model,
        When the view appears and setup completes,
        Then it emits finished once
        """)
    func onAppearEmitsFinished() async {
        let sut = withDependencies {
            makeDependencies(&$0)
        } operation: {
            BootstrapViewModel()
        }
        var events: [BootstrapViewModelEvent] = []
        sut.onEvent = { events.append($0) }

        sut.trigger(.onAppear)
        await sut.setupTask?.value

        #expect(events == [.finished])
    }

    @Test("""
        Given setup has already run,
        When the view appears again,
        Then setup does not run a second time
        """)
    func onAppearTwiceFinishesOnce() async {
        let sut = withDependencies {
            makeDependencies(&$0)
        } operation: {
            BootstrapViewModel()
        }
        var events: [BootstrapViewModelEvent] = []
        sut.onEvent = { events.append($0) }

        sut.trigger(.onAppear)
        await sut.setupTask?.value
        sut.trigger(.onAppear)
        await sut.setupTask?.value

        #expect(events == [.finished])
    }
}

/// Safe shared defaults for this suite. Each test overrides only what it asserts on.
private func makeDependencies(_ dependencies: inout DependencyValues) {
    dependencies.logger.log = { _, _, _ in }
    dependencies.logger.logError = { _, _ in }
}
