import BootstrapFeature
import Dependencies
import Logging
import TaskBoardFeature
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
        Then the coordinator shows the Task Board
        """)
    func bootstrapFinishedNavigatesToTaskBoard() {
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

        guard case .taskBoard? = sut.screen else {
            Issue.record("Expected .taskBoard, got \(String(describing: sut.screen))")
            return
        }
    }

    @Test("""
        Given a coordinator showing the Task Board,
        When it navigates to the Task Board again,
        Then a fresh Task Board view model is created
        """)
    func navigatingToTaskBoardCreatesFreshViewModel() {
        let sut = withDependencies {
            makeDependencies(&$0)
        } operation: {
            AppCoordinator(initialRoute: .taskBoard)
        }
        guard case .taskBoard(let first)? = sut.screen else {
            Issue.record("Expected .taskBoard")
            return
        }

        sut.navigate(to: .taskBoard)

        guard case .taskBoard(let second)? = sut.screen else {
            Issue.record("Expected .taskBoard")
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
