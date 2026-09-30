import Combine
import Dependencies
import L10n
import Logging
// >>> effect
import __Client__
// <<< effect

/// All of `__Feature__`'s logic. MainActor via the module's default isolation (ADR 0005).
///
/// Contract (ADR 0003):
/// - `state` is read-only outside the class.
/// - `trigger(_:)` is the only input. It's synchronous and called by the View only.
/// - `onEvent` is the only output. It's a plain closure set by the parent after `init`.
/// - `init` stores state and does nothing else: no dependency reads, no work.
public final class __Feature__ViewModel: ObservableObject {
    @Published public private(set) var state: __Feature__ViewState
    public var onEvent: ((__Feature__ViewModelEvent) -> Void)?

    // Dependencies: all declared here, at class level.
    @Dependency(\.logger) private var logger
    // >>> effect
    @Dependency(\.__client__) private var __client__

    /// Internal (not private) so tests can `await sut.loadTask?.value` instead of sleeping.
    var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    // <<< effect

    public init(state: __Feature__ViewState = __Feature__ViewState()) {
        self.state = state
    }

    // >>> effect
    deinit {
        loadTask?.cancel()
    }
    // <<< effect

    public func trigger(_ event: __Feature__ViewEvent) {
        switch event {
        // >>> effect
        case .onAppear:
            guard state.content == nil else { return }
            load()
        case .retryTapped:
            load()
        // <<< effect
        case .closeTapped:
            logger.debug("__Feature__ close tapped")
            onEvent?(.closeRequested)
        }
    }

    // >>> effect
    // MARK: - Internal actions

    /// Results of effects. They come back here and never through `__Feature__ViewEvent`.
    private enum InternalAction {
        case loaded(String)
        case loadFailed(any Error)
    }

    /// The only place effect results touch `state`.
    private func handle(_ action: InternalAction) {
        switch action {
        case .loaded(let content):
            state.isLoading = false
            state.content = content
            state.errorMessage = nil
        case .loadFailed(let error):
            state.isLoading = false
            state.errorMessage = L10n.Common.genericError
            logger.error(error, ["feature": "__Feature__", "operation": "load"])
        }
    }

    // MARK: - Effects

    private func load() {
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let client = __client__  // read dependencies before the Task starts
        state.isLoading = true
        state.errorMessage = nil

        loadTask = Task { [weak self] in
            let action: InternalAction
            do {
                action = .loaded(try await client.load())
            } catch {
                action = .loadFailed(error)
            }
            // Re-check after every await: the run may have been cancelled or superseded.
            guard !Task.isCancelled, let self, self.loadGeneration == generation else { return }
            self.handle(action)
        }
    }

    // CPU-heavy work must leave the main actor explicitly. Plain `await client.x()` calls don't
    // need this; the client's own I/O suspends. Example:
    //
    // @concurrent
    // private static func parse(_ data: Data) async throws -> [Item] { … }
    // <<< effect
}
