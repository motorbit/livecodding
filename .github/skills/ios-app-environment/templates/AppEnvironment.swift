import Foundation

/// The backends/configurations the app can run against. Add cases only for real, separately
/// deployed environments.
public enum AppEnvironment: String, CaseIterable, Codable, Sendable {
    case prod
    case nonProd
}

/// Everything that differs per environment. Non-secret values only: this ships in the binary.
public struct EnvironmentConfig: Equatable, Sendable {
    public var environment: AppEnvironment
    public var apiBaseURL: URL

    public init(environment: AppEnvironment, apiBaseURL: URL) {
        self.environment = environment
        self.apiBaseURL = apiBaseURL
    }
}

/// Values injected at build time (see the `buildtime-*` option in the skill). Both environments'
/// configs are compiled in, so a debug/non-prod build can switch at runtime; `defaultEnvironment`
/// is what the build targets.
public struct BuildValues: Equatable, Sendable {
    public var defaultEnvironment: AppEnvironment
    public var configs: [AppEnvironment: EnvironmentConfig]
    /// Debug builds and non-prod builds allow a runtime override; prod release builds never do.
    public var allowsOverride: Bool

    public init(defaultEnvironment: AppEnvironment, configs: [AppEnvironment: EnvironmentConfig], allowsOverride: Bool) {
        self.defaultEnvironment = defaultEnvironment
        self.configs = configs
        self.allowsOverride = allowsOverride
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
