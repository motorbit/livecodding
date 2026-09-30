import Dependencies
import Logging
import Testing
@testable import HomeFeature

@MainActor
struct HomeViewModelTests {
    @Test("""
        Given a view model,
        When close is tapped,
        Then it emits closeRequested once
        """)
    func closeTappedEmitsCloseRequested() {
        let sut = withDependencies {
            makeDependencies(&$0)
        } operation: {
            HomeViewModel()
        }
        var events: [HomeViewModelEvent] = []
        sut.onEvent = { events.append($0) }

        sut.trigger(.closeTapped)

        #expect(events == [.closeRequested])
    }

}

/// Safe shared defaults for this suite. Each test overrides only what it asserts on. Endpoints
/// that aren't stubbed stay unimplemented and fail the test if they're called.
private func makeDependencies(_ dependencies: inout DependencyValues) {
    dependencies.logger.log = { _, _, _ in }
    dependencies.logger.logError = { _, _ in }
}
