import BootstrapFeature
import Dependencies
import HomeFeature
import Logging
import Testing
@testable import AppCoordinator

@MainActor
struct AppCoordinatorTests {
    @Test("""
        Given a new coordinator,
        When it is created with the default route,
        Then it shows the bootstrap screen
        """)
    func initialScreenIsBootstrap() {
        let sut = withDependencies {
            makeDependencies(&$0)
        } operation: {
            AppCoordinator()
        }

        guard case .bootstrap? = sut.screen else {
            Issue.record("Expected .bootstrap, got \(String(describing: sut.screen))")
            return
        }
    }

    @Test("""
        Given the bootstrap screen,
        When bootstrap finishes,
        Then the coordinator shows home
        """)
    func bootstrapFinishedNavigatesToHome() {
        let sut = withDependencies {
            makeDependencies(&$0)
        } operation: {
            AppCoordinator()
        }
        guard case .bootstrap(let bootstrap)? = sut.screen else {
            Issue.record("Expected .bootstrap")
            return
        }

        bootstrap.onEvent?(.finished)

        guard case .home? = sut.screen else {
            Issue.record("Expected .home, got \(String(describing: sut.screen))")
            return
        }
    }

    @Test("""
        Given a coordinator showing home,
        When it navigates to home again,
        Then a fresh Home view model is created
        """)
    func navigatingToHomeCreatesFreshViewModel() {
        let sut = withDependencies {
            makeDependencies(&$0)
        } operation: {
            AppCoordinator(initialRoute: .home)
        }
        guard case .home(let first)? = sut.screen else {
            Issue.record("Expected .home")
            return
        }

        sut.navigate(to: .home)

        guard case .home(let second)? = sut.screen else {
            Issue.record("Expected .home")
            return
        }
        #expect(first !== second)
    }
}

/// Safe shared defaults for this suite (child VMs may log). Tests override only what they assert on.
private func makeDependencies(_ dependencies: inout DependencyValues) {
    dependencies.logger.log = { _, _, _ in }
    dependencies.logger.logError = { _, _ in }
}
