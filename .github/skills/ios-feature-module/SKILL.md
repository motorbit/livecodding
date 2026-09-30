---
name: ios-feature-module
description: Creates a new SwiftUI feature as its own local SPM module (target + test target) following the kit's MVVM contract. The module gets a View, ViewState, ViewEvent, ViewModelEvent, a ViewModel with InternalAction and stored-Task effects, an optional StateMaker, and Swift Testing tests. Use when the user asks to "add a feature", "new screen", "create a module for X" or "scaffold a view model".
---

# iOS feature module

## Purpose

This skill scaffolds `Modules/Sources/<Feature>Feature/` and `Modules/Tests/<Feature>FeatureTests/`, following ADR 0003 (MVVM contract), ADR 0005 (concurrency) and ADR 0006 (testing). It then hands off to **ios-coordinator-route** or embeds the feature in a host feature.

## Inputs / Options

| Option | Values | Default |
|---|---|---|
| `Feature` | UpperCamelCase name, e.g. `Profile` → `__Feature__`; lowerCamel `profile` → `__feature__`. Strip a trailing `View`/`Screen`/`Feature` (`FlickrView` → `Flickr`, otherwise you get `FlickrViewView`) | required |
| Async effect | yes (loads data through a client) / no (static screen) | ask |
| Client | existing client module + key path (`__Client__`, `__client__`), e.g. `ProfileClient` / `profileClient`, **or** "new" | required if effect = yes |
| Data source (new client only) | endpoint/base URL + path, auth (none / API key / token), response fields the screen needs | required if Client = new |
| StateMaker | yes (initial state needs inputs/dependencies/computation) / no | no |
| Placement | top-level route (coordinator) / embedded child of `<HostFeature>` / sheet from `<HostFeature>` / push onto `<HostFeature>`'s NavigationStack | ask |

### Ask once, completely

If the request doesn't state these options, ask **one** `ask_user` form that covers **every** missing option above in a single round, including the conditional ones. Don't split it into a second round:
- Show the normalized `Feature` name as the default so the user can correct it.
- For Client, list the existing client modules from `Package.swift` plus "new (describe the data source)". Put the Data source fields (endpoint, auth, fields) in the same form, marked "only if new".
- For Placement, list all four values, with the host defaulting to the current root feature (e.g. `Home`).

If the client doesn't exist yet, run **ios-dependency-client** first (see "New API client" below).

## Worker mode (ios-app-autopilot)

When you run as a parallel worker, the orchestrator has already added the module to `Package.swift` and owns every shared file. Then:
- Skip step 6 (Package.swift and the test plan) and step 7 (placement); report needed deps and output events instead.
- In step 5, don't touch `Localizable.xcstrings` or `L10n.swift`. Write accessors in `Modules/Sources/L10n/L10n+__Feature__.swift` (`extension L10n { public enum __Feature__ { … } }`) with `String(localized: "<key>", defaultValue: "<value>", bundle: .module)`, and report the keys.
- Skip the AGENTS.md Module map update.

## Steps

1. **Resolve the options.** Check the Module enum in `Modules/Package.swift` so you don't create a duplicate name.
2. **Copy the sources** into `Modules/Sources/__Feature__Feature/`:
   - `templates/__Feature__View.swift`
   - `templates/__Feature__ViewState.swift`
   - `templates/__Feature__ViewEvent.swift`
   - `templates/__Feature__ViewModelEvent.swift`
   - `templates/__Feature__ViewModel.swift`
   - `templates/README.md`
   - If StateMaker = yes, also copy `templates/__Feature__StateMaker.swift`. Then change the VM init default to `__Feature__StateMaker.live()`.
3. **Copy the tests** into `Modules/Tests/__Feature__FeatureTests/`:
   - `templates/Tests/__Feature__ViewModelTests.swift`
   - If StateMaker = yes, also copy `templates/Tests/__Feature__StateMakerTests.swift`.
4. **Substitute the placeholders** `__Feature__`, `__feature__`, `__Client__` and `__client__`.
   - If effect = **no**, delete every block between `// >>> effect` and `// <<< effect`, including the markers.
   - If effect = **yes**, delete only the marker lines.
   - Adapt the sample endpoint `load() async throws -> String` to the real client API.
5. **Localize.** Add the keys to `Modules/Sources/L10n/Resources/Localizable.xcstrings`, and add a `public enum __Feature__` to `L10n.swift`. It needs at least `title`. Add `greeting(_:)` only if you use the StateMaker sample. Key format: `__feature__.title`.
6. **Package.swift.** Merge `templates/Package.snippet.swift`:
   - Add the Module case.
   - Add `uiModule(...)` with its dependencies and testDependencies.
   - **Test plan:** run `python3 .github/skills/ios-project-bootstrap/scripts/sync_test_plan.py <Root>/<App>.xctestplan`. This adds `__Feature__FeatureTests` so it runs from the app scheme (⌘U). If the plan doesn't exist yet, the script says so. Create it with ios-project-bootstrap's `wire_xcode_project.py` (step 9).
7. **Place the feature:**
   - *Top-level route:* run **ios-coordinator-route**.
   - *Embedded child / sheet:* in the host VM, create the child with `withDependencies(from: self) { __Feature__ViewModel() }`, wire `onEvent`, and store the child in host state. Add `.module(.__feature__Feature)` to the host's dependencies. See "Child presentation" below.
   - *Push:* same ownership as a sheet, plus a host route enum and path. See "Push presentation (NavigationStack)" below.
8. **Fill in the module README** (owner, wiring, gotchas). Update `AGENTS.md` Module map.

## Templates

| File | Notes |
|---|---|
| `templates/__Feature__ViewModel.swift` | `@Observable final class`; `trigger` / `onEvent`; `InternalAction` + `handle`; stored `loadTask` + generation guard |
| `templates/__Feature__View.swift` | Renders state and forwards events, with `#Preview`s |
| `templates/__Feature__ViewState.swift` | `Equatable` struct with defaults from L10n |
| `templates/__Feature__ViewEvent.swift`, `__Feature__ViewModelEvent.swift` | Input / output enums |
| `templates/__Feature__StateMaker.swift` | Optional: pure `make(_:)` + `live()` adapter |
| `templates/Tests/*.swift` | Swift Testing: happy path, error, stale-result race, no-reload |
| `templates/Package.snippet.swift` | Manifest additions |

## Child presentation (current simple approach)

- The host owns the child VM, typically as an optional field in the host VM, e.g. `var detail: DetailViewModel?`. Present it with `.sheet(item:)`. Classes can be `Identifiable` through the default `ObjectIdentifier`: `extension DetailViewModel: Identifiable {}`.
- The host sets the field in response to an event and clears it on the child's `.closeRequested`.
- The View binds with `Binding(get: { vm.detail }, set: { if $0 == nil { vm.trigger(.detailDismissed) } })`. This way dismissal still goes through `trigger`.
- Parents never call the child's `trigger`. They talk to the child only through the child's `onEvent`.

## Push presentation (NavigationStack)

Use this when the user picks "push onto `<Host>`'s NavigationStack". The **host feature** owns the stack, and it's scoped to that host. `AppCoordinator` never gets a NavigationStack (top-level screens are routes, not pushes). Reference implementation: `HomeFeature` → `FlickrFeature`.

- **Host state** (`<Host>ViewState.swift`, or a separate `<Host>Route.swift`):
  ```swift
  public enum <Host>Route: Hashable, Sendable { case __feature__ }
  public var navigationPath: [<Host>Route] = []
  ```
- **Host events:** `__feature__Tapped` and `navigationPathChanged([<Host>Route])`.
- **Host VM** owns `public private(set) var __feature__ViewModel: __Feature__ViewModel?`:
  ```swift
  case .__feature__Tapped:
      guard !state.navigationPath.contains(.__feature__) else { return }   // double-tap guard
      let child = withDependencies(from: self) { __Feature__ViewModel() }
      child.onEvent = { [weak self] in self?.handle($0) }
      __feature__ViewModel = child
      state.navigationPath.append(.__feature__)
  case .navigationPathChanged(let path):                                      // system back / swipe
      state.navigationPath = path
      if !path.contains(.__feature__) { __feature__ViewModel = nil }
  ```
  The child's `.closeRequested`, if it has one, pops the route (`removeAll { $0 == .__feature__ }`) and clears the child.
- **Host View:**
  ```swift
  NavigationStack(path: Binding(
      get: { viewModel.state.navigationPath },
      set: { viewModel.trigger(.navigationPathChanged($0)) }
  )) {
      content
          .navigationDestination(for: <Host>Route.self) { route in
              switch route {                      // exhaustive, no default:
              case .__feature__:
                  if let vm = viewModel.__feature__ViewModel { __Feature__View(viewModel: vm) }
              }
          }
  }
  ```
- **Pushed child View:** use `.navigationTitle(state.title)` instead of an in-body header, and rely on the system back button. Add a toolbar close only if the user asks for one. Check that no coordinator overlay (e.g. the debug environment button) covers the trailing toolbar area.
- **Rules:**
  - Put one NavigationStack per host. Never nest stacks, and never put a NavigationStack inside a pushed child.
  - The route enum carries only `Hashable` identifiers. Child VMs live in the host VM, not in the path.
  - Deeper pushes from the child: the child emits an output event, and the host appends another `<Host>Route` case and owns that VM too.
  - `.navigationBarTitleDisplayMode` and `.topBarTrailing` are iOS-only APIs. That's fine here, because the package is iOS-only.
- **Host tests:**
  - Tapping creates the child and pushes the route.
  - A second tap is ignored.
  - `navigationPathChanged([])` clears the child.
  - The child's `.closeRequested`, if present, pops the route and clears the child.

## Navigation beyond a single host stack — TBD

Push from a host feature is decided (above). Still **undecided** (README ▸ Open questions): deep state set from the root (deep links into a pushed screen), cross-feature `Destination` enums, and a stack owned by the coordinator. **Don't invent these.** Ask the user.

## New API client (when Client = new)

Run **ios-dependency-client** with these defaults so you don't need another round:
- Create a separate `<Domain>Client` client module that depends on `NetworkClient`. Its live value reads `@Dependency(\.networkClient)` and builds an `Endpoint` per call. Domain models (`Sendable`, `Equatable`) live in the client module. DTOs stay internal.
- Every file imports what it uses. The feature's View/State/StateMaker must `import <Domain>Client` if they touch domain types, and the client must `import NetworkClient`.
- Client tests call the live value **inside** `withDependencies { … } operation: { try await client.fetch() }`. Awaiting after the scope loses the override.

## Layout defaults

- In grids of remote images with unknown aspect ratios, give cells a fixed height: `.frame(maxWidth: .infinity).frame(height: 140).clipped()`. Don't use `aspectRatio(contentMode: .fill)`, because it produces uneven or overlapping cells.
- Once the user has seen the UI, **don't change the layout** unless they ask. That includes review-driven fixes: apply only the findings, and list any extra change separately before making it.

## Rules / Checklist

- The View uses DesignSystem tokens only (`.dsTitle`, `Color.dsTextPrimary`, `.padding(.md)`, `.dsPrimary`), with no literal fonts, colors or paddings. DesignSystem always exists; if the project dropped a token group, replace those lines with the tokens it has.
- The View is presentation only: no `if` on business rules, no `Task`, no `@Dependency`, no formatting and no L10n lookups. Static labels are fine, but prefer state fields.
- State is a plain `Equatable` struct. It has no computed logic or custom `==`, and its strings are already localized.
- VM:
  - `public private(set) var state`.
  - A synchronous `trigger(_:)`.
  - A single plain `onEvent: ((Event) -> Void)?`. It isn't `@Sendable`, and it doesn't use `assumeIsolated`.
- `init` has at most `state:` with a default value. It reads no dependencies and does no work.
- All dependencies are `@ObservationIgnored @Dependency(\.x) private var x` at class level.
- Async work:
  - Keep a stored `Task` and cancel it before a restart.
  - Use a generation counter, not a `Bool` flag.
  - Guard `!Task.isCancelled`, `self` and the generation after every `await`.
  - Report results through `InternalAction` → `handle(_:)`.
  - Cancel in `deinit`.
- Use `@concurrent` only for CPU-heavy helpers. Never add `DispatchQueue.main` or `MainActor.run` in a UI module; it's already MainActor.
- Never use `default:` in a `switch` over your own enums.
- `ViewModelEvent` is `Equatable`. Add `Sendable` only if it crosses isolation.
- Import other features only to embed them. Never `import AppCoordinator`.
- Don't declare a `@DependencyClient` in a feature module. Put it in a client module (ios-dependency-client).
- Tests:
  - `@MainActor` suites with `@Test("""Given …, When …, Then …""")` and camelCase names.
  - A file-level `makeDependencies(&$0)` plus per-test overrides. No `makeSUT`.
  - No `Task.sleep`. Instead, `await sut.loadTask?.value`, or use an `AsyncStream` gate for races.

## Done criteria

- No placeholders or `>>> effect` markers remain: `grep -rn "__\(F\|f\)eature__\|__\(C\|c\)lient__\|>>> effect\|<<< effect" Modules`.
- The Module case, `uiModule(...)` entry and test target exist, and every imported module is listed in the dependencies.
- L10n keys exist in both `L10n.swift` and `Localizable.xcstrings`.
- `__Feature__FeatureTests` (and any new client's test target) is in the `.xctestplan`, so `sync_test_plan.py` prints "already in sync".
- The feature is reachable, either as a route in the coordinator or embedded in the host, and its `onEvent` is wired.
- Tests cover: each output event, the load success and failure paths, and the stale-result race (effect = yes). For push: push, double-tap, pop, and child close.
- **Verify proportionally:**
  - Logic, Package or import changes: compile once with `cd Modules && swift build --build-tests --triple arm64-apple-ios16.0-simulator`. The package is iOS-only, so plain `swift test` targets macOS and fails on `@Observable`. Never run two SwiftPM commands at the same time, because they share the `.build` lock.
  - Layout-only changes: no build. The user checks them in Xcode.
- **Don't run `xcodebuild`** unless asked. Tell the user to build and run the tests in Xcode.
