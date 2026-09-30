import Dependencies
import Logging
import Observation

/// Start-up work that must finish before the first real screen, e.g. restoring a session,
/// fetching remote config or running migrations. It does nothing yet and finishes immediately.
///
/// Contract (ADR 0003): `trigger(_:)` in, `onEvent` out, `init` stores state only.
@Observable
public final class BootstrapViewModel {
    public private(set) var state: BootstrapViewState
    public var onEvent: ((BootstrapViewModelEvent) -> Void)?

    @ObservationIgnored @Dependency(\.logger) private var logger

    /// Internal (not private) so tests can `await sut.setupTask?.value` instead of sleeping.
    @ObservationIgnored var setupTask: Task<Void, Never>?
    @ObservationIgnored private var setupGeneration = 0

    public init(state: BootstrapViewState = BootstrapViewState()) {
        self.state = state
    }

    deinit {
        setupTask?.cancel()
    }

    public func trigger(_ event: BootstrapViewEvent) {
        switch event {
        case .onAppear:
            guard setupTask == nil else { return }  // start-up runs once per screen
            runSetup()
        }
    }

    // MARK: - Internal actions

    private enum InternalAction {
        case setupFinished
    }

    private func handle(_ action: InternalAction) {
        switch action {
        case .setupFinished:
            logger.debug("Bootstrap finished")
            onEvent?(.finished)
        }
    }

    // MARK: - Effects

    private func runSetup() {
        setupTask?.cancel()
        setupGeneration += 1
        let generation = setupGeneration
        // Read the dependencies the setup steps need here, before the Task starts.

        setupTask = Task { [weak self] in
            // Start-up steps go here, e.g. `try await session.restore()`. Map their results to
            // `InternalAction`s and re-check the guard below after every `await`.
            guard !Task.isCancelled, let self, self.setupGeneration == generation else { return }
            self.handle(.setupFinished)
        }
    }
}
