import AppEnvironment
import Dependencies
import Foundation
import Logging
import Testing
@testable import DebugMenuFeature

@MainActor
struct DebugMenuViewModelTests {
    private let configs = [
        EnvironmentConfig(environment: .local, apiBackend: .mock),
        EnvironmentConfig(environment: .dev, apiBackend: .remote(URL(string: "http://localhost:8080")!)),
        EnvironmentConfig(environment: .prod, apiBackend: .notConfigured),
    ]

    @Test("""
        Given selectable environments with dev active,
        When the menu appears,
        Then it lists every environment with its backend and marks dev as selected
        """)
    func onAppearListsEnvironments() {
        let sut = withDependencies {
            makeDependencies(&$0, current: .dev)
        } operation: {
            DebugMenuViewModel()
        }

        sut.trigger(.onAppear)

        #expect(sut.state.environments == [
            DebugMenuEnvironmentRow(id: .local, name: "Local", detail: "In-app mock", isSelected: false),
            DebugMenuEnvironmentRow(id: .dev, name: "Dev", detail: "http://localhost:8080", isSelected: true),
            DebugMenuEnvironmentRow(id: .prod, name: "Prod", detail: "Not configured", isSelected: false),
        ])
    }

    @Test("""
        Given local is active,
        When another environment is selected,
        Then the VM requests the environment change
        """)
    func selectingAnotherEnvironmentRequestsChange() {
        let sut = withDependencies {
            makeDependencies(&$0, current: .local)
        } operation: {
            DebugMenuViewModel()
        }
        var events: [DebugMenuViewModelEvent] = []
        sut.onEvent = { events.append($0) }

        sut.trigger(.environmentSelected(.dev))

        #expect(events == [.environmentChangeRequested(.dev)])
    }

    @Test("""
        Given local is active,
        When local is selected again or close is tapped,
        Then the VM only asks to close
        """)
    func selectingCurrentEnvironmentCloses() {
        let sut = withDependencies {
            makeDependencies(&$0, current: .local)
        } operation: {
            DebugMenuViewModel()
        }
        var events: [DebugMenuViewModelEvent] = []
        sut.onEvent = { events.append($0) }

        sut.trigger(.environmentSelected(.local))
        sut.trigger(.closeTapped)

        #expect(events == [.closeRequested, .closeRequested])
    }

    private func makeDependencies(_ dependencies: inout DependencyValues, current: AppEnvironment) {
        let configs = configs
        dependencies.environmentClient.current = { configs.first { $0.environment == current }! }
        dependencies.environmentClient.selectableEnvironments = { configs }
        dependencies.logger.log = { _, _, _ in }
    }
}
