import L10n

/// OPTIONAL. Use it when the initial `__Feature__ViewState` needs inputs (config, flags, a model)
/// or computation. Otherwise delete this file and rely on `__Feature__ViewState.init` defaults.
///
/// - `make(_:)` is pure: same input, same state. Unit-test it directly.
/// - `live()` is the only place that reads dependencies. It runs in the caller's dependency context
///   (the coordinator's `withDependencies(from:)`), never inside the ViewModel's `init`.
///
/// Wire it as the VM's default argument:
///     public init(state: __Feature__ViewState = __Feature__StateMaker.live())
public enum __Feature__StateMaker {
    public struct Input: Equatable, Sendable {
        public var userName: String?

        public init(userName: String?) {
            self.userName = userName
        }
    }

    public static func make(_ input: Input) -> __Feature__ViewState {
        __Feature__ViewState(
            title: input.userName.map { L10n.__Feature__.greeting($0) } ?? L10n.__Feature__.title
        )
    }

    /// Reads dependencies, then delegates to `make`. Replace `userName: nil` with real reads, e.g.
    /// `@Dependency(\.sessionClient) var session` and `userName: session.currentUserName()`
    /// (and add `import Dependencies`).
    public static func live() -> __Feature__ViewState {
        make(Input(userName: nil))
    }
}
