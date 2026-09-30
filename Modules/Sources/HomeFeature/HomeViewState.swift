import L10n

/// Everything `HomeView` renders, ready to display. Plain data: no computed logic, no
/// formatting, no hand-written `==`. Strings are already localized.
///
/// Use `State.init` defaults when the initial state is static. When it needs inputs or
/// computation, build it in `HomeStateMaker` instead.
public struct HomeViewState: Equatable {
    public var title: String
    public var closeTitle: String

    public init(
        title: String = L10n.Home.title,
        closeTitle: String = L10n.Common.close,
    ) {
        self.title = title
        self.closeTitle = closeTitle
    }
}
