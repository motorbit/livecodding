import Combine
import Dependencies
import L10n
import Logging

/// All of `Home`'s logic. MainActor via the module's default isolation (ADR 0005).
///
/// Contract (ADR 0003):
/// - `state` is read-only outside the class.
/// - `trigger(_:)` is the only input. It's synchronous and called by the View only.
/// - `onEvent` is the only output. It's a plain closure set by the parent after `init`.
/// - `init` stores state and does nothing else: no dependency reads, no work.
public final class HomeViewModel: ObservableObject {
    @Published public private(set) var state: HomeViewState
    public var onEvent: ((HomeViewModelEvent) -> Void)?

    // Dependencies: all declared here, at class level.
    @Dependency(\.logger) private var logger

    public init(state: HomeViewState = HomeViewState()) {
        self.state = state
    }


    public func trigger(_ event: HomeViewEvent) {
        switch event {
        case .closeTapped:
            logger.debug("Home close tapped")
            onEvent?(.closeRequested)
        }
    }

}
