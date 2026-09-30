import L10n

/// Everything `BootstrapView` renders. Plain data: no computed logic, strings already localized.
public struct BootstrapViewState: Equatable {
    public var loadingLabel: String

    public init(loadingLabel: String = L10n.Bootstrap.loading) {
        self.loadingLabel = loadingLabel
    }
}
