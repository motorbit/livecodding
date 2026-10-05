import AppEnvironment
import L10n

/// Everything `DebugMenuView` renders. Plain data: no computed logic, strings already localized.
public struct DebugMenuViewState: Equatable {
    public var title: String
    public var environmentHeader: String
    public var environmentFooter: String
    public var closeTitle: String
    public var environments: [DebugMenuEnvironmentRow]

    public init(
        title: String = L10n.DebugMenu.title,
        environmentHeader: String = L10n.DebugMenu.environmentHeader,
        environmentFooter: String = L10n.DebugMenu.environmentFooter,
        closeTitle: String = L10n.Common.close,
        environments: [DebugMenuEnvironmentRow] = []
    ) {
        self.title = title
        self.environmentHeader = environmentHeader
        self.environmentFooter = environmentFooter
        self.closeTitle = closeTitle
        self.environments = environments
    }
}

/// One selectable environment: its name, where its API goes and whether it's active.
public struct DebugMenuEnvironmentRow: Equatable, Identifiable {
    public var id: AppEnvironment
    public var name: String
    public var detail: String
    public var isSelected: Bool

    public init(id: AppEnvironment, name: String, detail: String, isSelected: Bool) {
        self.id = id
        self.name = name
        self.detail = detail
        self.isSelected = isSelected
    }
}
