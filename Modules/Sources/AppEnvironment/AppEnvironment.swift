import Foundation

/// The backends the app can run against.
public enum AppEnvironment: String, CaseIterable, Codable, Sendable {
    /// In-app mock backend (`MockNetworkClient`): no server needed.
    case local
    /// Developer backend, by default the Go server in `backend/` on `http://localhost:8080`.
    case dev
    case prod
}

/// Where API calls go in one environment.
public enum APIBackend: Equatable, Sendable {
    /// The in-process mock. API clients that have one use it; others fail with `.notConfigured`.
    case mock
    case remote(URL)
    /// No base URL yet (e.g. prod before it's deployed). Requests fail with
    /// `EnvironmentError.apiBaseURLMissing`.
    case notConfigured

    /// A remote backend from a build value. An empty or invalid string means `.notConfigured`.
    public static func url(_ string: String) -> Self {
        guard !string.isEmpty, let url = URL(string: string), url.scheme != nil, url.host() != nil else {
            return .notConfigured
        }
        return .remote(url)
    }
}

/// Everything that differs per environment. Non-secret values only: this ships in the binary.
public struct EnvironmentConfig: Equatable, Sendable {
    public var environment: AppEnvironment
    public var apiBackend: APIBackend

    public init(environment: AppEnvironment, apiBackend: APIBackend) {
        self.environment = environment
        self.apiBackend = apiBackend
    }
}

public enum EnvironmentError: Error, Equatable, Sendable {
    /// The active environment has no API base URL configured.
    case apiBaseURLMissing(AppEnvironment)
}

/// Values injected at build time by `BuildValues+Generated.swift`. Every environment's config is
/// compiled in, so a debug/non-prod build can switch at runtime; `defaultEnvironment` is what the
/// build targets.
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
