import L10n

/// Everything `__Feature__View` renders, ready to display. Plain data: no computed logic, no
/// formatting, no hand-written `==`. Strings are already localized.
///
/// Use `State.init` defaults when the initial state is static. When it needs inputs or
/// computation, build it in `__Feature__StateMaker` instead.
public struct __Feature__ViewState: Equatable {
    public var title: String
    public var closeTitle: String
    // >>> effect
    public var isLoading: Bool
    public var content: String?
    public var errorMessage: String?
    public var retryTitle: String
    // <<< effect

    public init(
        title: String = L10n.__Feature__.title,
        closeTitle: String = L10n.Common.close,
        // >>> effect
        isLoading: Bool = false,
        content: String? = nil,
        errorMessage: String? = nil,
        retryTitle: String = L10n.Common.retry
        // <<< effect
    ) {
        self.title = title
        self.closeTitle = closeTitle
        // >>> effect
        self.isLoading = isLoading
        self.content = content
        self.errorMessage = errorMessage
        self.retryTitle = retryTitle
        // <<< effect
    }
}
