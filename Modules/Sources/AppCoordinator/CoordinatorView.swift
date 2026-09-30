import BootstrapFeature
import HomeFeature
import SwiftUI

/// Maps `coordinator.screen` to a View. App-wide overlays (lock screen, offline banner, debug
/// button) are layered in the `ZStack` above the screen. No logic and no top-level NavigationStack.
public struct CoordinatorView: View {
    private let coordinator: AppCoordinator

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        ZStack {
            if let screen = coordinator.screen {
                switch screen {
                case .bootstrap(let viewModel):
                    BootstrapView(viewModel: viewModel)
                case .home(let viewModel):
                    HomeView(viewModel: viewModel)
                }
            }
            // Overlays go here, each driven by optional state on the coordinator.
        }
    }
}
