# AGENTS.md — <App> iOS

Rules for AI agents and developers working in this repository. The **HARD RULES** are non-negotiable. The rest is guidance. Rationale lives in [`docs/decisions/`](docs/decisions/README.md).

## Overview

- **App:** `Livecodding`: starter iOS app; product purpose and target users are not yet specified.
- **Platform:** iOS 17+, Swift 6.2 (Swift 6 language mode), SwiftUI, Combine. Keep every app/module deployment target at iOS 17.0; newer APIs require availability checks or compatible alternatives.
- **Architecture:**
  - thin app shell + local SPM package `Modules/` (one module per feature/client);
  - root `AppCoordinator` (composition root);
  - event-driven MVVM;
  - DI with swift-dependencies;
  - Swift Testing.
- **Dependencies:** `swift-dependencies` (dependency injection); NetworkClient (unused scaffold) provides typed HTTP transport, JSON decoding and endpoint construction; `TaskClient` talks to a DTO-level `MockNetworkClient`.

## Module map

| Module | Kind | Purpose |
|---|---|---|
| `AppCoordinator` | UI (MainActor) | Composition root: routes → screens, output handling, route-entry effects |
| `BootstrapFeature` | UI (MainActor) | Start-up screen (initial route): runs setup before Task Board |
| `TaskBoardFeature` | UI (MainActor) | Task list host: loading/retry, pull-to-refresh, completion, swipe-delete with undo, search/sort, due text, Add sheet and detail push |
| `AddTaskFeature` | UI (MainActor) | Add-task sheet (incl. optional due date) owned by TaskBoardFeature |
| `TaskDetailFeature` | UI (MainActor) | Task editor (incl. due date) pushed within TaskBoardFeature's navigation stack |
| `DesignSystem` | UI (MainActor) | Color/typography/spacing tokens, basic components |
| `Logging` | client | `LoggingClient` (`\.logger`), an os.Logger wrapper |
| `L10n` | leaf | String Catalog + typed accessors |
| `NetworkClient` | client | HTTP transport + middlewares; scaffold for a future real backend, currently unused |
| `TaskClient` | client | Task repository (`TaskClient`) over the internal `TaskNetworkClient` boundary; live network = `MockNetworkClient` (latency, failures) |

<!-- Delete rows for modules the project doesn't have. Add every new module here. -->

## HARD RULES

Rule ids (`R1`…) are cited by the `ios-reviewer` agent.

1. **R1 Thin shell.** The app target holds only `@main App` (hosting `CoordinatorView`) and an optional forwarding `AppDelegate`. *Why:* all logic must be testable in modules (ADR 0001).
2. **R2 One module per feature.** Each feature/client is its own `Modules/` target with a test target, declared through `uiModule`/`clientModule`.
3. **R3 Import direction.** Nothing imports `AppCoordinator`. A feature imports another feature only to embed or present it as a child. Routing goes through the coordinator (ADR 0002).
4. **R4 Pure `makeScreen`.** It creates the VM (`withDependencies(from: self)`) and wires `onEvent`, nothing else. App-level route-entry policy (session timers, resets) goes in `didEnter(_:)`. Data loading, logging and analytics (including screen views) belong to the feature VM.
5. **R5 View = presentation.** A View observes its `ObservableObject` ViewModel with `@ObservedObject` (the app root uses `@StateObject`), renders `state` and calls `trigger(.event)`. It has no logic, no `Task`, no `@Dependency` and no formatting. Strings come from state.
6. **R6 State = data.** `XxxViewState` is a plain `Equatable` struct with no computed logic.
7. **R7 VM contract.**
   - `ObservableObject` class, `@Published public private(set) var state`, sync `trigger(_:)`. The only allowed async entry point is `refresh() async` for `.refreshable`, which triggers and then awaits the stored load task (ADR 0003).
   - A single plain `onEvent` closure (not `@Sendable`, no `assumeIsolated`).
   - `init(state:)` with a default at most. No work or dependency reads in `init` (ADR 0003).
8. **R8 Effects.** Async results come back as `InternalAction` → `handle(_:)`. Tasks are stored and cancelled before a restart and in `deinit`, guarded by a generation counter and `Task.isCancelled` after every `await`. No `Bool` re-entrancy flags (ADR 0005).
9. **R9 DI.**
   - `@DependencyClient` structs live in client modules, never in UI modules. One client module may group related clients (e.g. `Storage`: Keychain + UserDefaults + SwiftData; `NetworkClient`: REST + GraphQL).
   - `testValue = Self()` (unimplemented). No no-op test values.
   - Consumers use `@Dependency` at class level; non-published dependency and task properties need no observation wrapper.
   - No UseCase layer without a second real consumer (ADR 0004).
10. **R10 Isolation.**
    - UI modules use `.defaultIsolation(MainActor.self)`, and client modules stay nonisolated. Both enable `NonisolatedNonsendingByDefault` and `InferIsolatedConformances`.
    - CPU-heavy or blocking work is `@concurrent`.
    - No `DispatchQueue.main` or `MainActor.run` in UI modules.
11. **R11 Exhaustive switches.** No `default:` over the project's own enums.
12. **R12 Strings.** User-facing text comes from `L10n` (String Catalog). It's resolved in the VM/StateMaker/State defaults, and never hardcoded in features.
13. **R13 Logging and privacy.**
    - No `print`. Use `\.logger`.
    - Never log tokens, credentials, bodies or PII. Analytics parameters carry categories, not free text.
14. **R14 Tests.**
    - Swift Testing with `@Test("""Given …, When …, Then …""")` and camelCase names.
    - `makeDependencies(&$0)` + per-test overrides. No `makeSUT`.
    - No `Task.sleep`: await stored tasks, gate with `AsyncStream`, use `ImmediateClock`.
    - Changed behaviour ships with tests.
15. **R15 Shared modules.** A shared module (`Utils`, `CommonUI`, `TestSupport`, …) is fine once code is used by **≥2 modules**. It never imports features. **Exception:** `DesignSystem` always exists, even with a single feature. Don't copy helpers from other projects without reviewing them; each must justify itself here.
16. **R16 Project file.** Agents never edit `*.pbxproj`. Give the user manual Xcode steps instead. **Exception:** the bootstrap skill's `wire_xcode_project.py` (adds `Modules/`, links `AppCoordinator`, sets build settings, creates `<App>.xctestplan` + the shared scheme).
17. **R17 Secrets.** No secrets in source, xcconfig, Info.plist or generated files.

## Open decisions (don't invent a pattern)

- **Push navigation** is decided only for a **host-scoped NavigationStack**: the host feature owns `[<Host>Route]` and the child VMs (see `ios-feature-module` ▸ Push presentation). Still **TBD**: deep state from the root, cross-feature `Destination` enums, and coordinator-owned stacks. Ask before adding any of these.

## Where to look (skills)

| Task | Skill |
|---|---|
| Set up a new project / Modules package | `ios-project-bootstrap` |
| New screen / feature module | `ios-feature-module` |
| Add or wire a top-level route, entry effects | `ios-coordinator-route` |
| Wrap an API/SDK/system service | `ios-dependency-client` |
| HTTP layer (JSON, endpoints, auth refresh, retry, logging, correlation id) | `ios-network-client` |
| Colors, fonts, spacing, components | `ios-design-system` |
| Keychain / UserDefaults / SwiftData | `ios-storage` |
| Clarify a brief before building | `ios-grill` |
| Brief → working app, autonomously | `ios-app-autopilot` |
| Product analytics | `ios-analytics` |
| prod/nonProd config, runtime switch | `ios-app-environment` |
| Review a change against these rules | `ios-reviewer` agent |

## Build and test

```bash
# From <Root>/Modules. Agents: don't run these unless the user asks. The user builds in Xcode.
xcodebuild test -scheme Modules-Package -destination 'platform=iOS Simulator,name=<Simulator>'
xcodebuild test -scheme Modules-Package -destination '…' -only-testing:<Module>Tests
# App (from <Root>)
xcodebuild build -project <App>.xcodeproj -scheme <App> -destination '…'
# After adding a module with tests: register its test target in the app's test plan (idempotent)
python3 .github/skills/ios-project-bootstrap/scripts/sync_test_plan.py <App>.xctestplan
```

<!-- Add lint/format commands (SwiftLint, swift-format) and the CI workflow name if they exist. -->

## Workflow preferences

- Before coding, read the target module's `README.md` and the relevant skill. Follow local patterns.
- Keep changes small and focused. Don't refactor unrelated code in the same change.
- Parameterized skills: take the options from the request, and **ask one short multi-choice question** for anything missing. Apply only the selected parts.
- Don't create or edit Xcode project files (except through `wire_xcode_project.py` during bootstrap). List the manual Xcode steps for the user.
- After a change, update the module `README.md` and this file's Module map if a module was added.
- Before handing over, run the `ios-reviewer` agent on the changed files and fix the ❌ findings.
- Branches: `<type>/<ticket>-<short-name>`. Commits: `<type>(<ticket>): <summary>`. <adjust to team convention>
