---
name: ios-network-client
description: Adds a NetworkClient module, a URLSession async `data(for:)` wrapped as a swift-dependencies client. Optional, independently selectable middlewares/extensions cover JSON decoding with typed errors, an Endpoint builder, auth token injection with single-flight refresh-on-401, sanitized request logging, retry with backoff, and a correlation-ID header. Use when the user says "add networking", "HTTP client", "API client", "network layer", "refresh token on 401", "retry requests" or "correlation id".
---

# iOS network client

## Purpose

This skill creates `Modules/Sources/NetworkClient/`. It starts as a clean minimal client (`send: (URLRequest) async throws -> (Data, HTTPURLResponse)`) and adds **only the options the user selected**. Cross-cutting behaviour is implemented as `NetworkMiddleware` decorators around the transport. Each middleware is a pure function of its injected inputs, so it's testable with closure stubs.

## Inputs / Options

| # | Option | Adds (templates) | Requires |
|---|---|---|---|
| 0 | **core** (always) | `core/NetworkClient.swift`, `core/NetworkMiddleware.swift`, `core/LiveNetworkClient.swift`, `Tests/core/*` | — |
| 1 | `json`: Codable decode + typed errors | `json/NetworkError.swift`, `json/NetworkClient+JSON.swift`, `Tests/json/*` | — |
| 2 | `endpoint`: Endpoint/Request builder | `endpoint/Endpoint.swift`, `Tests/endpoint/*` | json |
| 3 | `auth`: token provider + single-flight refresh-on-401 | `auth/AuthTokenProvider.swift`, `auth/NetworkMiddleware+Auth.swift`, `Tests/auth/*` | — |
| 4 | `logging`: sanitized request logging | `logging/NetworkMiddleware+Logging.swift`, `Tests/logging/*` | Logging module |
| 5 | `retry`: exponential backoff + jitter | `retry/NetworkMiddleware+Retry.swift`, `Tests/retry/*` | — |
| 6 | `correlation`: `X-Correlation-ID` header | `correlation/NetworkMiddleware+CorrelationID.swift`, `Tests/correlation/*` | — |

**If the user didn't specify the options, ask one multi-choice question:** "NetworkClient options? [json] [endpoint] [auth refresh-on-401] [logging] [retry] [correlation-id] [none: minimal]". Apply only the selected parts. If `endpoint` is selected, add `json` automatically and say so.

## Steps

1. **Resolve the options.** Check that `Package.swift` has no `networkClient` case yet.
2. **Core.** Copy `templates/core/*` → `Modules/Sources/NetworkClient/` and `templates/Tests/core/*` → `Modules/Tests/NetworkClientTests/`. The core test file defines the shared `HTTPURLResponse.stub` helper, so always copy it.
3. **Each selected option.** Copy its folder's files into `Sources/NetworkClient/` (flat, no subfolders) and its tests into `Tests/NetworkClientTests/`.
4. **Compose the live value.** In `LiveNetworkClient.swift`, handle the `// >>> option:<name>` … `// <<< option:<name>` blocks:
   - For selected options, delete only the marker lines.
   - For unselected options, delete the whole block.

   Keep the order **correlation → retry → auth → logging → transport**.
5. **Package.swift.** Merge `templates/Package.snippet.swift` and resolve its option markers the same way. Then add `NetworkClientTests` to the test plan with `python3 .github/skills/ios-project-bootstrap/scripts/sync_test_plan.py <Root>/<App>.xctestplan`. If the plan doesn't exist yet, the script says so. Create it with ios-project-bootstrap's `wire_xcode_project.py` (step 9).
6. **auth only.** `AuthTokenProvider` is only an interface (`TestDependencyKey`). Tell the user that the module owning sign-in must add `extension AuthTokenProvider: DependencyKey { static let liveValue = … }`. Auth/SSO SDK integration is out of scope for this kit.
7. **API clients.** Features don't call `NetworkClient`. For each backend area, create an API client with **ios-dependency-client**, e.g. `ProfileClient.fetchProfile`, whose live value uses `@Dependency(\.networkClient)` and an `Endpoint` or `URLRequest`. It gets the base URL from `AppEnvironment` if that module exists, or from a constant otherwise.
8. **README** for the module: list the enabled options, the concurrency model (`@concurrent` checked entry points), the middleware order and the redaction rules.

## Rules / Checklist

- The transport (`URLSession`) is touched in exactly one function (`urlSessionTransport`).
- Under `NonisolatedNonsendingByDefault`, client code runs on the caller's actor. The checked entry points `decode(_:for:)` and `sendChecked(_:)` are therefore **`@concurrent`**: the whole exchange (middlewares, transport, status check, decoding) runs off the caller's actor, and the caller resumes on its own actor with the result. Raw `send(_:)` stays on the caller's actor; API clients use the checked entry points.
- Logging never records headers, bodies or query values. It never uses `print`. Failures are logged as the mapped `NetworkError`, never the raw error (`URLError.userInfo` holds the full failing URL). Cancellation is logged at `.debug`, not as an error.
- Retries apply only to idempotent methods and transient failures. The retry `clock` is injected (`\.continuousClock` in live, `ImmediateClock()` in tests). Cancellation stops retrying.
- Auth refreshes **once** per rejected token (single-flight actor) and retries once. A second 401 is returned to the caller.
- The correlation ID is set once per logical request, outside retry, so every attempt shares it.
- `testValue = NetworkClient()` is unimplemented. Tests construct `NetworkClient { request in … }` or compose middlewares around a closure. They never hit the network.
- Errors surfaced to features are `NetworkError`. Map them to user-facing text in the VM (L10n), never in the client.

## Done criteria

- Only the selected option files exist. `grep -rn ">>> option\|<<< option" Modules/Sources/NetworkClient Modules/Package.swift` returns nothing.
- `liveComposed()` references only middlewares whose files exist.
- Each selected option has its tests copied.
- **Don't run `xcodebuild`** unless asked. Tell the user to build and run `NetworkClientTests`.
