/// Where the app can go. A value: carries identity/context (ids, URLs, modes), never loaded data.
/// Every case needs a matching `AppScreen` case, a `makeScreen` branch and a `didEnter` branch.
public enum AppRoute: Equatable, Sendable {
    /// Start-up screen; the default initial route.
    case bootstrap
    case taskBoard
}
