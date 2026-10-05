import AppEnvironment
import L10n

/// Builds `DebugMenuViewState` rows from environment configs.
enum DebugMenuStateMaker {
    static func rows(configs: [EnvironmentConfig], current: AppEnvironment) -> [DebugMenuEnvironmentRow] {
        configs.map { config in
            DebugMenuEnvironmentRow(
                id: config.environment,
                name: name(config.environment),
                detail: detail(config.apiBackend),
                isSelected: config.environment == current
            )
        }
    }

    private static func name(_ environment: AppEnvironment) -> String {
        switch environment {
        case .local: L10n.DebugMenu.environmentLocal
        case .dev: L10n.DebugMenu.environmentDev
        case .prod: L10n.DebugMenu.environmentProd
        }
    }

    private static func detail(_ backend: APIBackend) -> String {
        switch backend {
        case .mock: L10n.DebugMenu.backendMock
        case .remote(let url): url.absoluteString
        case .notConfigured: L10n.DebugMenu.backendNotConfigured
        }
    }
}
