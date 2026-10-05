import AppEnvironment
import Combine
import Dependencies
import Logging

/// Developer tools for debug and non-prod builds. Right now: switching the backend environment.
///
/// Contract (ADR 0003): `trigger(_:)` in, `onEvent` out, `init` stores state only. The coordinator
/// owns the switch itself (persist + ordered reset); this VM only asks for it.
public final class DebugMenuViewModel: ObservableObject {
    @Published public private(set) var state: DebugMenuViewState
    public var onEvent: ((DebugMenuViewModelEvent) -> Void)?

    @Dependency(\.environmentClient) private var environmentClient
    @Dependency(\.logger) private var logger

    public init(state: DebugMenuViewState = DebugMenuViewState()) {
        self.state = state
    }

    public func trigger(_ event: DebugMenuViewEvent) {
        switch event {
        case .onAppear:
            state.environments = DebugMenuStateMaker.rows(
                configs: environmentClient.selectableEnvironments(),
                current: environmentClient.current().environment
            )
        case .environmentSelected(let environment):
            guard environment != environmentClient.current().environment else {
                onEvent?(.closeRequested)
                return
            }
            logger.info("Environment change requested", ["environment": environment.rawValue])
            onEvent?(.environmentChangeRequested(environment))
        case .closeTapped:
            onEvent?(.closeRequested)
        }
    }
}
