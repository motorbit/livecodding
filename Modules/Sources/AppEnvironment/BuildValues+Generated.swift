import Foundation

// Build values. This committed file holds the LOCAL DEFAULTS; set the base URLs here.
// CI regenerates it before building with `scripts/generate-build-values.sh`. Don't commit a
// CI-generated version. To keep local edits out of git: `git update-index --skip-worktree <this file>`.
extension BuildValues {
    public static let current = BuildValues(
        defaultEnvironment: .local,
        configs: [
            .local: EnvironmentConfig(environment: .local, apiBackend: .mock),
            .dev: EnvironmentConfig(environment: .dev, apiBackend: .url("http://localhost:8080")),
            // TODO: Fill in when prod is deployed. While empty, requests fail with `apiBaseURLMissing`.
            .prod: EnvironmentConfig(environment: .prod, apiBackend: .url("")),
        ],
        allowsOverride: true
    )
}
