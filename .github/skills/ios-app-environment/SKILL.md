---
name: ios-app-environment
description: Adds an AppEnvironment module with prod/nonProd configs. Values are injected at build time (xcconfig → Info.plist, or a CI-generated Swift file), and an `EnvironmentClient` resolves the active config, with a runtime override for debug and non-prod builds only. It also covers the ordered reset on switching. Use when the user says "environments", "prod/non-prod", "staging", "base URL per environment", "switch environment at runtime", "debug menu environment" or "xcconfig".
---

# iOS app environment

## Purpose

This skill creates `Modules/Sources/AppEnvironment/`, so there's one place that answers "which backend is this build talking to?". Both environments' **non-secret** configs are compiled in. The build selects the default. Debug and non-prod builds may override it at runtime, and prod release builds never can.

## Inputs / Options

| Option | Values | Default |
|---|---|---|
| Build-time source | `buildtime-infoplist`: xcconfig → Info.plist → `Bundle.main` | ask |
| | `buildtime-generated`: CI runs a script that writes a Swift file | |
| Config fields | `apiBaseURL` + any others (non-secret only) | `apiBaseURL` |
| Runtime override | yes (debug/non-prod) / no | yes |
| Environments | `prod`, `nonProd` (+ others only if separately deployed) | prod, nonProd |

**If not specified, ask:** "Environment config source? [xcconfig + Info.plist (Xcode-native, easy per-configuration values)] [CI-generated Swift file (no Xcode settings, values from CI env vars)]. Runtime override in debug builds? [yes] [no]".

## Steps

1. **Resolve the options.**
2. **Copy the core sources** into `Modules/Sources/AppEnvironment/`:
   - `templates/AppEnvironment.swift`
   - `templates/EnvironmentClient.swift`
   - `templates/LiveEnvironmentClient.swift`

   Add fields to `EnvironmentConfig` if needed, and keep the source parsers in sync.
3. **Build-time source.**
   - *buildtime-infoplist*:
     1. Copy `BuildValues+InfoPlist.swift` into the module.
     2. Copy `Environment.xcconfig` to `<Root>/Config/Environment.xcconfig`.
     3. Copy `Info.plist` to `<Root>/Config/Info.plist` (next to the xcconfig). **Not** into `<App>/`: that folder is a synchronized group, so Xcode would copy the file into the bundle and fail with "Multiple commands produce …/Info.plist".
     4. Wire the project: run `ios-project-bootstrap/scripts/wire_xcode_project.py <Root>/<App>.xcodeproj` (again, if bootstrap already ran it; it's idempotent). When `Config/Info.plist` and `Config/Environment.xcconfig` exist, it sets the target's `INFOPLIST_FILE = Config/Info.plist` and assigns `Environment.xcconfig` as the project's base configuration. The user needs no manual Xcode steps.
     5. Never add `Info.plist` or `Environment.xcconfig` to a target or its Copy Bundle Resources phase: it causes "Multiple commands produce …/Info.plist". Keep "Generate Info.plist File" = Yes; Xcode merges the two.
     6. Check that `ApiBaseHost*` shows in the built app's Info.plist.
   - *buildtime-generated*:
     1. Copy `BuildValues+Generated.swift` into the module. It holds the committed local defaults.
     2. Copy `generate-build-values.sh` to `<Root>/scripts/` and make it executable.
     3. Tell the user to run the script in CI before `xcodebuild`, with `APP_ENVIRONMENT`, `API_BASE_URL_PROD` and `API_BASE_URL_NONPROD` set.
4. **Tests:** copy `templates/Tests/EnvironmentClientTests.swift` → `Modules/Tests/AppEnvironmentTests/`. Resolve the `>>> option:buildtime-infoplist` block: keep it for the Info.plist option, and delete it otherwise.
5. **Package.swift:** merge `templates/Package.snippet.swift`. Then add `AppEnvironmentTests` to the test plan with `python3 .github/skills/ios-project-bootstrap/scripts/sync_test_plan.py <Root>/<App>.xctestplan`. If the plan doesn't exist yet, the script says so. Create it with ios-project-bootstrap's `wire_xcode_project.py` (step 9).
6. **Consumers read per call.** API clients call `environmentClient.current().apiBaseURL` inside each request, never once in a `liveValue`. That way a switch takes effect after the reset.
7. **Runtime override** (option). Build the switch UI as a normal feature with **ios-feature-module**, e.g. `DebugMenuFeature`:
   - Its VM reads `selectableEnvironments()`. If the list is empty, the feature isn't offered.
   - It emits `.environmentChangeRequested(AppEnvironment?)`.
   - The coordinator presents it as an overlay (see ios-coordinator-route). Show it through a debug gesture or a hidden button, never in prod release.
8. **Ordered reset** on a switch. It's one coordinator method, e.g. `switchEnvironment(to:)`, and runs in this order:
   1. `environmentClient.setOverride(env)`
   2. Cancel in-flight work and drop the current screen.
   3. Clear environment-bound state: tokens (keychain `deleteAll`), caches and analytics `reset()`, for the modules that exist.
   4. `navigate(to: <initial route>)`

   Add a coordinator test that asserts this order with a `LockIsolated<[String]>` call log.

## Rules / Checklist

- Never put secrets (API keys, client secrets) in xcconfig, Info.plist or generated Swift. Anything there is in the binary. Secrets come from a backend or CI-signed configuration outside this kit.
- Prod release: `allowsOverride == false`, and any stale override is ignored and removed.
- `EnvironmentClient.testValue` is unimplemented. Tests stub `current` with an explicit `EnvironmentConfig`. Live tests use an isolated `UserDefaults(suiteName:)`.
- The environment is **never** a compile-time `#if PROD` branch in feature code. Features don't know about environments at all.
- The app shell does nothing. `BuildValues.current` is read lazily by `liveValue`.

## Done criteria

- Exactly one `BuildValues+*.swift` source exists, and no `>>> option` markers or `__App__` remain.
- The manual Xcode or CI steps were given for the chosen source.
- API clients read `current()` per request, and the coordinator has a tested ordered-reset method (if the override is enabled).
- **Don't run `xcodebuild`** unless asked.
