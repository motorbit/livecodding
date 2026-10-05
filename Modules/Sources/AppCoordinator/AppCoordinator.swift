import AppEnvironment
import BootstrapFeature
import Combine
import DebugMenuFeature
import Dependencies
import Logging
import TaskBoardFeature
import TaskClient

/// Composition root. Turns an `AppRoute` into a live `AppScreen`, wires the screen's output events
/// and runs route-entry effects. Features never import this module (ADR 0002).
public final class AppCoordinator: ObservableObject {
    /// `nil` only while `init` runs; always set once `init` returns.
    @Published public private(set) var screen: AppScreen?
    /// The debug menu overlay (a sheet over any screen). Not a route.
    @Published public private(set) var debugMenu: DebugMenuViewModel?
    /// The floating button that opens it; `nil` when the build can't switch environments
    /// (prod release).
    public var debugMenuButton: DebugMenuButtonState? {
        environmentClient.selectableEnvironments().isEmpty ? nil : DebugMenuButtonState()
    }

    // The coordinator's own dependencies. `withDependencies(from: self)` propagates the context
    // through these, so keep at least one `@Dependency` here.
    @Dependency(\.logger) private var logger
    @Dependency(\.environmentClient) private var environmentClient
    @Dependency(\.taskClient) private var taskClient

    var cacheResetTask: Task<Void, Never>?

    public init(initialRoute: AppRoute = .bootstrap) {
        navigate(to: initialRoute)
    }

    deinit {
        cacheResetTask?.cancel()
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

    // MARK: - Debug menu overlay

    /// Opens the debug menu (floating button). Does nothing when the build doesn't allow switching
    /// environments (prod release) or the menu is already open.
    public func openDebugMenu() {
        guard debugMenu == nil, debugMenuButton != nil else { return }
        let viewModel = withDependencies(from: self) { DebugMenuViewModel() }
        viewModel.onEvent = { [weak self] event in self?.handle(event) }
        debugMenu = viewModel
    }

    /// The sheet was dismissed interactively. Guarded: SwiftUI also calls this after a programmatic
    /// dismissal, while it updates the view.
    public func debugMenuDismissed() {
        guard debugMenu != nil else { return }
        debugMenu = nil
    }

    /// Ordered reset on an environment switch:
    /// 1. persist the override;
    /// 2. drop the overlay and the current screen, which cancels in-flight work (VMs cancel their
    ///    tasks in `deinit`);
    /// 3. clear environment-bound state: the task cache (async; a failure is logged by `TaskClient`
    ///    and the next fetch replaces the cache anyway). Add tokens and analytics reset here;
    /// 4. start over from the initial route. It doesn't wait for step 3: cache rows are tagged with
    ///    their environment, so the new screens never read the old environment's tasks.
    func switchEnvironment(to environment: AppEnvironment) {
        logger.notice("Switching environment", ["environment": environment.rawValue])
        environmentClient.setOverride(environment)
        debugMenu = nil
        screen = nil
        cacheResetTask?.cancel()
        let client = taskClient
        cacheResetTask = Task { try? await client.clearCache() }
        navigate(to: .bootstrap)
    }

    // MARK: - Child output

    private func handle(_ event: BootstrapViewModelEvent) {
        switch event {
        case .finished:
            navigate(to: .taskBoard)
        }
    }

    private func handle(_ event: DebugMenuViewModelEvent) {
        switch event {
        case .environmentChangeRequested(let environment):
            switchEnvironment(to: environment)
        case .closeRequested:
            debugMenu = nil
        }
    }
}
