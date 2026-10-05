import BootstrapFeature
import DebugMenuFeature
import TaskBoardFeature
import SwiftUI

/// Maps `coordinator.screen` to a View. App-wide overlays (lock screen, offline banner, debug
/// button) are layered in the `ZStack` above the screen. No logic and no top-level NavigationStack.
public struct CoordinatorView: View {
    @ObservedObject private var coordinator: AppCoordinator

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        ZStack {
            if let screen = coordinator.screen {
                switch screen {
                case .bootstrap(let viewModel):
                    BootstrapView(viewModel: viewModel)
                case .taskBoard(let viewModel):
                    TaskBoardView(viewModel: viewModel)
                }
            }
            // Overlays go here, each driven by optional state on the coordinator.
            if let debugMenuButton = coordinator.debugMenuButton {
                DebugMenuButton(state: debugMenuButton) { coordinator.openDebugMenu() }
                    .padding(.leading, .md)
                    .padding(.bottom, .xxl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .sheet(isPresented: Binding(
            get: { coordinator.debugMenu != nil },
            set: { if !$0 { coordinator.debugMenuDismissed() } }
        )) {
            if let debugMenu = coordinator.debugMenu {
                DebugMenuView(viewModel: debugMenu)
            }
        }
    }
}
