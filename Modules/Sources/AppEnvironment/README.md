# AppEnvironment

Answers "which backend is this build talking to?". Every environment's **non-secret** config is compiled in; the build picks the default, and debug and non-prod builds can override it at runtime (Debug Menu). Prod release builds never can.

## Environments

| Environment | API backend | Default value |
|---|---|---|
| `local` | `.mock`: the in-app `MockNetworkClient` (latency, ~15% failures), no server needed | always |
| `dev` | `.remote(URL)`: the Go server in `backend/` | `http://localhost:8080` |
| `prod` | `.remote(URL)`, or `.notConfigured` while empty | empty (TODO: fill in when deployed) |

`.notConfigured` makes API calls fail with `EnvironmentError.apiBaseURLMissing(env)`, which is logged and shown as the usual load error.

## Where to set the base URL

- **Locally:** edit `BuildValues+Generated.swift` (default environment and URLs). To keep the edit out of git: `git update-index --skip-worktree Modules/Sources/AppEnvironment/BuildValues+Generated.swift`.
- **CI:** run `scripts/generate-build-values.sh` before `xcodebuild`:

  ```bash
  APP_ENVIRONMENT=prod API_BASE_URL_PROD=https://api.example.com scripts/generate-build-values.sh
  ```

  `APP_ENVIRONMENT` is `local | dev | prod`. `API_BASE_URL_DEV` defaults to `http://localhost:8080`; plain `http` is accepted only for local hosts (`localhost`, `*.local`, unqualified names), because ATS allows only those, and only in Debug builds (`Config/Debug-Info.plist`); `API_BASE_URL_PROD` must be `https` and is required when `APP_ENVIRONMENT=prod`.

## Public API

| Type | Role |
|---|---|
| `EnvironmentClient` (`\.environmentClient`) | `current()`, `selectableEnvironments()` (empty in prod release), `setOverride(_:)` |
| `AppEnvironment`, `APIBackend`, `EnvironmentConfig` | Values |
| `BuildValues` | Build-time input (`BuildValues+Generated.swift`) |
| `EnvironmentError` | `.apiBaseURLMissing` |

## Rules

- API clients read `current()` **per request**, never once in a `liveValue`, so a switch applies after the coordinator's reset (`AppCoordinator.switchEnvironment(to:)`).
- Features don't know about environments, except `DebugMenuFeature`, which lists them.
- Overrides are stored in `UserDefaults` (`environment.override`). In a prod release build a stale override is ignored and removed.
- `testValue` is unimplemented; tests stub `current` / `selectableEnvironments`.
