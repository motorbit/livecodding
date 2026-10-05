import Foundation

extension EnvironmentClient {
    static let overrideKey = "environment.override"

    /// - `defaults` is injected so tests use an isolated suite (`UserDefaults(suiteName:)`).
    /// - An override is honoured only if `build.allowsOverride`. A stale override stored by a debug
    ///   build is ignored (and removed) in a prod release build.
    static func live(build: BuildValues, defaults: UserDefaults) -> Self {
        let store = OverrideStore(defaults: defaults)

        @Sendable func resolved() -> EnvironmentConfig {
            let environment: AppEnvironment
            if build.allowsOverride, let override = store.read(), build.configs[override] != nil {
                environment = override
            } else {
                if !build.allowsOverride { store.write(nil) }
                environment = build.defaultEnvironment
            }
            guard let config = build.configs[environment] else {
                preconditionFailure("Missing build values for \(environment)")
            }
            return config
        }

        return Self(
            current: { resolved() },
            selectableEnvironments: {
                build.allowsOverride ? AppEnvironment.allCases.compactMap { build.configs[$0] } : []
            },
            setOverride: { environment in
                guard build.allowsOverride else { return }
                store.write(environment)
            }
        )
    }
}

/// `UserDefaults` is documented as thread-safe. This wrapper is the only place it's captured, so
/// the Sendable claim holds whatever the SDK annotates.
private struct OverrideStore: @unchecked Sendable {
    let defaults: UserDefaults

    func read() -> AppEnvironment? {
        defaults.string(forKey: EnvironmentClient.overrideKey).flatMap(AppEnvironment.init(rawValue:))
    }

    func write(_ environment: AppEnvironment?) {
        if let environment {
            defaults.set(environment.rawValue, forKey: EnvironmentClient.overrideKey)
        } else {
            defaults.removeObject(forKey: EnvironmentClient.overrideKey)
        }
    }
}
