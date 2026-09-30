import Dependencies
import DependenciesMacros
import Foundation

/// Which environment the app talks to right now. Clients read `current()` **per call** (never
/// cache it in a `liveValue`), so an environment switch takes effect after the coordinator's reset.
@DependencyClient
public struct EnvironmentClient: Sendable {
    /// The active config: the runtime override if allowed and set, else the build default.
    public var current: @Sendable () -> EnvironmentConfig = { .placeholder }
    /// Environments selectable at runtime. Empty when overrides aren't allowed (prod release),
    /// so debug UI hides itself.
    public var selectableEnvironments: @Sendable () -> [AppEnvironment] = { [] }
    /// Persists an override (`nil` = back to the build default). The caller must then trigger the
    /// coordinator's ordered reset. Ignored when overrides aren't allowed.
    public var setOverride: @Sendable (_ environment: AppEnvironment?) -> Void
}

extension EnvironmentClient: DependencyKey {
    public static let liveValue = EnvironmentClient.live(build: .current, defaults: .standard)

    public static let previewValue = EnvironmentClient(
        current: { .placeholder },
        selectableEnvironments: { AppEnvironment.allCases },
        setOverride: { _ in }
    )

    /// Unimplemented. Tests stub `current` with the config they need.
    public static let testValue = EnvironmentClient()
}

public extension DependencyValues {
    var environmentClient: EnvironmentClient {
        get { self[EnvironmentClient.self] }
        set { self[EnvironmentClient.self] = newValue }
    }
}

public extension EnvironmentConfig {
    /// Used for previews and as the unimplemented-endpoint fallback. Never a real backend.
    static let placeholder = EnvironmentConfig(environment: .nonProd, apiBaseURL: URL(string: "https://example.invalid")!)
}
