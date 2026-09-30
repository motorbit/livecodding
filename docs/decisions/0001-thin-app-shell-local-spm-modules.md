# 0001 — Thin app shell + one local SPM module per feature

- **Status:** Accepted
- **Scope:** Project structure

## Context and problem

When all code lives in the app target, every file can see every other file. Build times grow with the target, previews rebuild everything, and nothing stops a view from reaching into a network layer. Boundaries that exist only by convention erode within months. We want boundaries that the **compiler** enforces, fast incremental builds and previews, and a project file that never needs merge-conflict surgery.

## Decision

1. The Xcode app target is a **thin shell**:
   - `@main struct <App>App: App` creates the root `AppCoordinator` and hosts `CoordinatorView`. Nothing else happens there.
   - An `AppDelegate` exists only when a system callback must be forwarded (URL handling, push token), and it only forwards to a module.
   - No logic, no `prepareDependencies`, no SDK setup and no logging in the shell.
2. All code lives in one **local Swift package** `Modules/` next to the `.xcodeproj`. The app links **only** `AppCoordinator`.
3. **One module per feature** (`XxxFeature`) and per client/infrastructure concern (`XxxClient`, `Logging`, `L10n`, …). Each has its own test target `XxxTests`.
4. The manifest is data-driven:
   - an `enum Module: String, CaseIterable` lists the modules,
   - `uiModule(...)` / `clientModule(...)` helpers generate the target plus its test target with the right Swift settings (ADR 0005),
   - every product is derived from the enum.
5. Dependency direction:
   - `AppCoordinator` → features → clients → leaves (`Logging`, `L10n`).
   - A feature may import another feature **only to embed or present it as a child**. Routing between top-level screens goes through the coordinator (ADR 0002).
   - Nothing imports `AppCoordinator`.
6. Shared modules (`Utils`, `CommonUI`, `TestSupport`, …) are allowed once **two or more** modules need the code. They never import features. Helpers aren't copied in from other projects without review; until a second consumer appears, code stays in its module.
7. A client module may group **related** clients (e.g. `Storage` = Keychain + UserDefaults + SwiftData; `NetworkClient` = REST + GraphQL). Unrelated clients get separate modules.

## Consequences

- ✅ Illegal imports fail to compile. Each module's public API is explicit (`public`).
- ✅ Previews and tests build only the module and its dependencies.
- ✅ The `.pbxproj` barely changes, because new files and modules are added in `Modules/`.
- ⚠️ More `public` boilerplate, and cross-module generics and inlining need care.
- ⚠️ SPM resources require `Bundle.module`. Previews need the package products linked. The bootstrap skill's `wire_xcode_project.py` adds `Modules/` as a folder and links `AppCoordinator`; it's the only sanctioned `.pbxproj` edit (R16).
- ⚠️ Tests of package modules run without a host app, so there's no keychain entitlement and no app `Info.plist`. Design live clients so their logic can be tested without those (see the keychain and environment skills).

## Alternatives considered

- **Single app target with folders.** It's simplest, but there are no enforced boundaries and builds are slower. Rejected.
- **Xcode framework targets.** They give enforced boundaries, but heavy `.pbxproj` churn and more signing/embedding configuration. Rejected.
- **Tuist/XcodeGen generated projects.** They're powerful, but add a tool dependency. Local SPM gives most of the benefit with no extra tooling. We can revisit this if the module count exceeds ~40.
- **Feature = folder inside a few big modules.** It's a compromise, and the boundaries leak again. Rejected.

## More information

- Skills: `ios-project-bootstrap`, `ios-feature-module`.
- Universal takeaway: make the architecture's boundaries **compile-time facts**. If a rule can be enforced by the module graph, don't leave it to code review.
