import AppEnvironment
import BootstrapFeature
import Combine
import DebugMenuFeature
import Dependencies
import Foundation
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

    @Test("""
        Given a build that allows switching environments,
        When the debug menu button is used and the menu is closed,
        Then the button is shown and the overlay appears and disappears
        """)
    func debugMenuOpensAndCloses() {
        let sut = withDependencies {
            makeDependencies(&$0)
        } operation: {
            AppCoordinator(initialRoute: .taskBoard)
        }

        sut.openDebugMenu()
        let menu = sut.debugMenu
        menu?.onEvent?(.closeRequested)

        #expect(sut.debugMenuButton != nil)
        #expect(menu != nil)
        #expect(sut.debugMenu == nil)
    }

    @Test("""
        Given a prod release build without selectable environments,
        When the debug menu is requested,
        Then neither the button nor the menu is shown
        """)
    func debugMenuUnavailableInProdRelease() {
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.environmentClient.selectableEnvironments = { [] }
        } operation: {
            AppCoordinator(initialRoute: .taskBoard)
        }

        sut.openDebugMenu()

        #expect(sut.debugMenuButton == nil)
        #expect(sut.debugMenu == nil)
    }

    @Test("""
        Given the debug menu was already closed by a button,
        When SwiftUI reports the sheet dismissal,
        Then the coordinator publishes nothing
        """)
    func debugMenuDismissedIsIdempotent() {
        let sut = withDependencies {
            makeDependencies(&$0)
        } operation: {
            AppCoordinator(initialRoute: .taskBoard)
        }
        var changes = 0
        let cancellable = sut.objectWillChange.sink { changes += 1 }

        sut.debugMenuDismissed()

        #expect(changes == 0)
        cancellable.cancel()
    }

    @Test("""
        Given the Task Board with the debug menu open,
        When another environment is requested,
        Then the override is saved before the old screen is dropped and the app restarts from bootstrap
        """)
    func environmentSwitchRunsOrderedReset() {
        let calls = LockIsolated<[String]>([])
        let sut = withDependencies {
            makeDependencies(&$0)
            $0.environmentClient.setOverride = { environment in
                calls.withValue { $0.append("setOverride(\(environment?.rawValue ?? "nil"))") }
            }
            $0.logger.log = { _, message, metadata in
                if message == "Navigate" { calls.withValue { $0.append("navigate(\(metadata["route"] ?? ""))") } }
            }
        } operation: {
            AppCoordinator(initialRoute: .taskBoard)
        }
        weak var oldTaskBoard: TaskBoardViewModel?
        if case .taskBoard(let viewModel)? = sut.screen { oldTaskBoard = viewModel }
        sut.openDebugMenu()
        calls.setValue([])

        sut.debugMenu?.onEvent?(.environmentChangeRequested(.dev))

        #expect(calls.value == ["setOverride(dev)", "navigate(bootstrap)"])
        #expect(sut.debugMenu == nil)
        #expect(oldTaskBoard == nil)
        guard case .bootstrap? = sut.screen else {
            Issue.record("Expected .bootstrap, got \(String(describing: sut.screen))")
            return
        }
    }
}

/// Safe shared defaults for this suite (child VMs may log). Tests override only what they assert on.
private func makeDependencies(_ dependencies: inout DependencyValues) {
    dependencies.logger.log = { _, _, _ in }
    dependencies.logger.logError = { _, _ in }
    dependencies.environmentClient.selectableEnvironments = {
        [EnvironmentConfig(environment: .local, apiBackend: .mock)]
    }
}
