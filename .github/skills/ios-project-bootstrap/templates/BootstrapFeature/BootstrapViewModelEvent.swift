/// Output from `BootstrapViewModel` to the coordinator, delivered through `onEvent`.
///
/// Add intent cases as start-up grows, e.g. `onboardingRequired`, `loginRequired`,
/// `updateRequired`. The coordinator maps each one to a route.
public enum BootstrapViewModelEvent: Equatable {
    /// Start-up work is done; the app can show its first real screen.
    case finished
}
