import BootstrapFeature
import Combine
import Dependencies
import Logging
import TaskBoardFeature

/// Composition root. Turns an `AppRoute` into a live `AppScreen`, wires the screen's output events
/// and runs route-entry effects. Features never import this module (ADR 0002).
public final class AppCoordinator: ObservableObject {
    /// `nil` only while `init` runs; always set once `init` returns.
    @Published public private(set) var screen: AppScreen?

    // The coordinator's own dependencies. `withDependencies(from: self)` propagates the context
    // through these, so keep at least one `@Dependency` here.
    @Dependency(\.logger) private var logger

    public init(initialRoute: AppRoute = .bootstrap) {
        navigate(to: initialRoute)
    }

    /// The single navigation entry point: build the screen, then run its entry effects.
    public func navigate(to route: AppRoute) {
        logger.debug("Navigate", ["route": "\(route)"])  // the coordinator's own log; features log themselves
        screen = makeScreen(for: route)
        didEnter(route)
    }

    // MARK: - Screen factory (pure: create + wire only)

    /// No analytics, fetching, timers or `Task` here. Data loading belongs to the feature VM
    /// (`trigger(.onAppear)`); route-entry effects belong to `didEnter(_:)`.
    private func makeScreen(for route: AppRoute) -> AppScreen {
        switch route {
        case .bootstrap:
            let viewModel = withDependencies(from: self) { BootstrapViewModel() }
            viewModel.onEvent = { [weak self] event in self?.handle(event) }
            return .bootstrap(viewModel)
        case .taskBoard:
            // `withDependencies(from: self)` gives the child the coordinator's dependency context,
            // so test overrides reach VMs created after `init`.
            let viewModel = withDependencies(from: self) { TaskBoardViewModel() }
            return .taskBoard(viewModel)
        }
    }

    // MARK: - Route-entry effects

    /// App-level policy that must run every time a route is entered. List every route; write
    /// explicit no-ops as `break`.
    private func didEnter(_ route: AppRoute) {
        switch route {
        case .bootstrap:
            break // Start-up work belongs to BootstrapViewModel.
        case .taskBoard:
            break // App-level policy only (session timer, reset, deep-link flush). Features log and track themselves.
        }
    }

    // MARK: - Child output

    private func handle(_ event: BootstrapViewModelEvent) {
        switch event {
        case .finished:
            navigate(to: .taskBoard)
        }
    }
}
