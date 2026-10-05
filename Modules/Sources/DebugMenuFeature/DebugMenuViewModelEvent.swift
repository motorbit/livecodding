import AppEnvironment

/// Output from `DebugMenuViewModel` to the coordinator, delivered through `onEvent`.
public enum DebugMenuViewModelEvent: Equatable {
    /// The user picked a different environment. The coordinator persists it and resets the app.
    case environmentChangeRequested(AppEnvironment)
    case closeRequested
}
