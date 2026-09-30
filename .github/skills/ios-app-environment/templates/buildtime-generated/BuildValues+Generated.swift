import Foundation

// Build values in Swift. This committed file holds LOCAL DEFAULTS (nonProd). CI regenerates it
// before building with `scripts/generate-build-values.sh`. Don't commit a CI-generated version.
// If you edit it locally, run `git update-index --skip-worktree <this file>`.
extension BuildValues {
    public static let current = BuildValues(
        defaultEnvironment: .nonProd,
        configs: [
            .prod: EnvironmentConfig(environment: .prod, apiBaseURL: URL(string: "https://api.example.com")!),
            .nonProd: EnvironmentConfig(environment: .nonProd, apiBaseURL: URL(string: "https://api.nonprod.example.com")!),
        ],
        allowsOverride: true
    )
}
