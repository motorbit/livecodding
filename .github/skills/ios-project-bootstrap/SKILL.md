---
name: ios-project-bootstrap
description: Bootstraps a new SwiftUI app targeting iOS 17+ created in Xcode into the modular layout, with a thin app shell, a local SPM package `Modules/`, a root coordinator, Logging, L10n, DesignSystem, a Bootstrap (start-up) screen and a first Home feature. It wires the package into the Xcode project automatically. Can also chain the optional AppEnvironment, Analytics, Network and Storage skills. Use when the user says "bootstrap", "set up the project", "new iOS app", "create Modules package" or "starter kit".
---

# iOS project bootstrap

## Purpose

This skill turns an empty Xcode "iOS App" project into the kit's architecture:
- The app target is a thin shell that only hosts `CoordinatorView`.
- All code lives in a local Swift package `Modules/` next to the `.xcodeproj`, with one target and one test target per module.
- `AppCoordinator` is the composition root.
- `Logging`, `L10n` and `DesignSystem` are the base modules. DesignSystem always exists, even with a single feature (the R15 exception).
- `BootstrapFeature` is the first screen. It's a start-up hook that finishes immediately for now. `HomeFeature` follows it.
- `Modules/` is added to the Xcode project as a folder, and `AppCoordinator` is linked to the app target by `scripts/wire_xcode_project.py` (the R16 exception). The user doesn't have to do any manual Xcode steps.

Read these first: `AGENTS.md` (hard rules) and ADRs 0001, 0002 and 0005 in `docs/decisions/`.

## Inputs / Options

| Option | Values | Default |
|---|---|---|
| `App` | App/Xcode project name, UpperCamelCase (replaces `__App__`) | from the `.xcodeproj` name |
| DesignSystem parts | colors (assets / code / none), typography (system / custom / none), tokens, components → runs **ios-design-system** | **all**: asset colors, system typography, tokens, components |
| AppEnvironment (prod/nonProd config) | yes / no → runs **ios-app-environment** | ask |
| Analytics | yes / no → runs **ios-analytics** | ask |
| NetworkClient | yes / no → runs **ios-network-client** | ask |
| Storage (Keychain / UserDefaults / SwiftData) | yes / no → runs **ios-storage** | ask |
| AppDelegate | yes (a system callback must be forwarded) / no | no |

DesignSystem and BootstrapFeature aren't options: they're always created. Use the default DesignSystem parts unless the user asks for different ones. Don't ask about them.

**If the user's request doesn't specify the optional modules, ask one short multi-choice question**, for example: "Which optional modules should I add? [AppEnvironment] [Analytics] [NetworkClient] [Storage] [none]". Then apply only the selected parts. Each chained skill asks its own sub-options unless the user already gave them.

## Preconditions (user does this manually)

The user creates the project in Xcode 26 or later: File ▸ New ▸ Project ▸ iOS App.
- Interface: SwiftUI. Language: Swift. Testing System: Swift Testing. Storage: None.
- Minimum deployment: iOS 17.0. Keep APIs compatible with iOS 17 or guard newer APIs with availability checks.

Find `<Root>/<App>.xcodeproj` and `<Root>/<App>/`. If they don't exist, stop and tell the user the steps above. The only `project.pbxproj` change allowed is through `scripts/wire_xcode_project.py` (step 9). Never edit it by hand.

## Steps

1. **Resolve options** as described above. Record `__App__`.
2. **Create the package** at `<Root>/Modules/`:
   - `Package.swift` ← `templates/Package.swift`. It already declares AppCoordinator, BootstrapFeature, HomeFeature, Logging, DesignSystem and L10n, and every target excludes its `README.md`.
   - `.gitignore` with `.build/`, `.swiftpm/` and `/Packages`.
3. **Base modules.** Copy each template and replace the placeholders:
   - `Sources/Logging/` ← `templates/Logging/*` (LoggingClient.swift, LiveLoggingClient.swift, README.md).
   - `Sources/L10n/` ← `templates/L10n/*` (L10n.swift, Resources/Localizable.xcstrings, README.md). They include `L10n.Bootstrap.loading` and `L10n.Home.title`.
   - `Sources/AppCoordinator/` ← `templates/AppCoordinator/*` (including README.md). The initial route is `.bootstrap`, and `BootstrapViewModelEvent.finished` navigates to `.home`.
   - `Tests/AppCoordinatorTests/` ← `templates/AppCoordinatorTests/AppCoordinatorTests.swift`.
4. **DesignSystem (always).** Run **ios-design-system** with the resolved parts (default: all). `Package.swift` already declares `designSystem` with `resources:`. Drop `resources:` only if there's no `Resources/` folder (colors in code and system typography).
5. **Bootstrap screen (always).**
   - `Sources/BootstrapFeature/` ← `templates/BootstrapFeature/*`.
   - `Tests/BootstrapFeatureTests/` ← `templates/BootstrapFeatureTests/*`.
   - If DesignSystem has no colors, remove the `.tint`/`.background` lines from `BootstrapView`.
6. **First feature.** Run the **ios-feature-module** skill with `Feature = Home` and **no async effect**: remove the `>>> effect … <<< effect` blocks. `Package.swift` already declares `homeFeature` (depending on DesignSystem). Keep `L10n.Home.title`. Adopt the DesignSystem tokens in `HomeView` (ios-design-system step 6), for example `.font(.dsTitle)`, `Color.dsTextPrimary`, `.padding(.md)` and `.buttonStyle(.dsPrimary)`.
7. **App shell.** In `<Root>/<App>/`:
   - Replace `<App>App.swift` with `templates/App/__App__App.swift`, substituting `__App__`.
   - Delete `ContentView.swift`.
   - Add `AppDelegate.swift` from `templates/App/AppDelegate.swift` **only if** the AppDelegate option is yes, and uncomment the adaptor line.
   - Xcode 26 projects use synchronized folders, so file changes in `<App>/` show up in Xcode without editing the project.
8. **Optional modules.** For each selected option, run its skill. Each skill adds a `Module` case, targets and wiring:
   - ios-app-environment
   - ios-analytics
   - ios-network-client
   - ios-storage

   Keep the `Module` enum grouped by layer.
9. **Wire the Xcode project.** Ask the user to close the project in Xcode if it's open, then run:
   ```bash
   python3 <this skill>/scripts/wire_xcode_project.py <Root>/<App>.xcodeproj --dry-run
   python3 <this skill>/scripts/wire_xcode_project.py <Root>/<App>.xcodeproj
   ```
   The script is idempotent. It:
   - adds `Modules/` to the Project navigator as a folder, which Xcode treats as a local package (the UCE style). An existing **Add Local…** package reference is converted to that style;
   - links `AppCoordinator` (only) to the app target;
   - with the AppEnvironment Info.plist option (`Config/Info.plist`, `Config/Environment.xcconfig`): sets `INFOPLIST_FILE` and assigns the xcconfig, so there are no manual steps;
   - sets iOS 17.0, Swift 6, MainActor default isolation, Approachable Concurrency and iPhone/iPad-only destinations, removing macOS/visionOS leftovers from multiplatform templates; optional `--iphone-only --portrait-only` flags narrow the app to iPhone portrait;
   - creates `<App>.xctestplan` next to the project, if it's missing, with every `Modules/Tests/*Tests` target, and adds it to the Project navigator. It also makes the plan the default of the shared `<App>` scheme: it creates the scheme if it's missing, or moves the scheme's `<Testables>` into the plan. If the scheme already uses another plan, the script warns and leaves it alone. Pass `--no-test-plan` to skip this.

   It refuses to run on a `project.pbxproj` with uncommitted changes. Show the user `git diff` of the file and re-run with `--allow-dirty` only if they agree. It validates the result with `plutil -lint` and restores the original on failure. If the app target isn't the only app target, pass `--target <App>`.

   The script creates the test plan, and skills that add a module later only keep it in sync with `scripts/sync_test_plan.py`.
10. **AGENTS.md.** Copy the kit's `AGENTS.md` to `<Root>/AGENTS.md`. Fill in the Overview and the Module map (BootstrapFeature and DesignSystem included), and remove the placeholder rows for modules that weren't selected.
11. **Hand over.** Tell the user:
    1. Reopen `<App>.xcodeproj`. `Modules` appears in the Project navigator, and AppCoordinator is linked under **General ▸ Frameworks, Libraries, and Embedded Content**.
    2. Package tests run from the app scheme (⌘U) through `<App>.xctestplan`, which step 9 created and filled. Alternatively, pick the `Modules-Package` scheme.
    3. Build (⌘B), then run the tests (⌘U) on a **simulator**. Package tests are tool-hosted, so a physical-device destination fails with "Tool-hosted testing is unavailable on device destinations". The app itself can still run on a device.

## Templates and scripts

- `templates/Package.swift`: the `Module` enum, `uiModule`/`clientModule` helpers and concurrency settings.
- `templates/App/__App__App.swift`, `templates/App/AppDelegate.swift` (optional).
- `templates/AppCoordinator/{AppRoute,AppScreen,AppCoordinator,CoordinatorView}.swift` and `README.md`.
- `templates/AppCoordinatorTests/AppCoordinatorTests.swift`.
- `templates/BootstrapFeature/*` and `templates/BootstrapFeatureTests/BootstrapViewModelTests.swift`.
- `templates/Logging/*` and `templates/L10n/*`.
- `scripts/wire_xcode_project.py`: the Xcode wiring, including creating the test plan and scheme (step 9). Run it with `-h` for its options.
- `scripts/sync_test_plan.py`: sync only. It adds missing `Modules/Tests/*Tests` targets to the existing `.xctestplan`. It's idempotent, keeps Xcode's formatting, and supports `--dry-run` and `--prune`. It fails if the plan is missing; run `wire_xcode_project.py` to create it. Every skill that adds a test target runs it.

## Rules / Checklist

- The app target contains only `@main App` and an optional forwarding `AppDelegate`. It has no logic, dependencies, logging or `prepareDependencies`.
- UI modules (features, AppCoordinator, DesignSystem) use `uiModule(...)`, which sets MainActor default isolation. Clients and leaves (Logging, L10n, *Client, Storage, Analytics, AppEnvironment) use `clientModule(...)`, which is nonisolated.
- Every source module has a `README.md` and a test target, except thin leaves (L10n, Logging, DesignSystem), which have no tests.
- Test targets list every module they import in `testDependencies`.
- Nothing imports `AppCoordinator`. Only `AppCoordinator` imports all features.
- DesignSystem is the one shared module created up front. Don't create other shared `Utils`/`TestSupport` modules until a second module needs the same code (R15).
- The package depends only on `swift-dependencies` (≥ 1.9). Add other packages only when a skill option needs them.
- `project.pbxproj` is changed only by `scripts/wire_xcode_project.py` (R16).

## Done criteria

- `grep -rn "__App__\|__Feature__\|__feature__\|__Client__\|__client__" <Root>/Modules <Root>/<App>` returns nothing.
- `Modules/Package.swift` lists exactly the base modules (AppCoordinator, BootstrapFeature, HomeFeature, Logging, DesignSystem, L10n) plus the selected ones. Each has sources, a README and tests (where `tests: true`).
- `<Root>/<App>/` contains only the App file, the optional AppDelegate and assets.
- A second run of `wire_xcode_project.py` prints "Already wired; nothing to change."
- `<App>.xctestplan` exists, appears in the Project navigator, is the shared `<App>` scheme's default plan, and lists every module test target. `sync_test_plan.py` prints "Test plan already in sync; nothing to change."
- **Don't run `xcodebuild`.** The user builds in Xcode. Offer the command only if asked: `xcodebuild test -scheme Modules-Package -destination 'platform=iOS Simulator,name=<device>'` from `Modules/`.
