---
name: ios-analytics
description: Adds a vendor-agnostic Analytics module with a `TrackingEvent` protocol (per-feature event enums, typed parameter values) and an `AnalyticsClient` swift-dependencies client that fans out to pluggable providers. It also covers naming validation, a PII sanitizer and test patterns. Use when the user says "analytics", "tracking", "track event", "screen view events", "add Firebase/Amplitude/Mixpanel/etc." or "telemetry events".
---

# iOS analytics

## Purpose

This skill creates `Modules/Sources/Analytics/`. Features describe *what happened* (`enum XxxEvent: TrackingEvent`). Only this module knows *where it goes* (`AnalyticsProvider`s). No vendor implementation ships by default. A vendor is added later as one provider file.

## Inputs / Options

| Option | Adds | Default |
|---|---|---|
| `identity` | `setUserID` / `reset` endpoints (pseudonymous id; cleared on sign-out) | yes |
| `log-provider` | `AnalyticsProvider.log(logger)`: debug-level unified-log output | yes |
| `sanitizer` | `AnalyticsSanitizer` for unavoidable free text (error descriptions) | yes |
| `vendor` | `AnalyticsProvider+Vendor.swift` adapter stub + Package hook | no |

**If the options aren't specified, ask:** "Analytics options? [identity (setUserID/reset)] [debug log provider] [PII sanitizer] [vendor adapter stub: which vendor?]". Apply only the selected ones.

## Steps

1. **Resolve the options.** The Logging module must exist (it's created by bootstrap).
2. **Copy the core sources** into `Modules/Sources/Analytics/`:
   - `templates/TrackingEvent.swift`
   - `templates/AnalyticsProvider.swift`
   - `templates/AnalyticsClient.swift`
3. **Options:**
   - `sanitizer`: copy `templates/AnalyticsSanitizer.swift`.
   - `vendor`: copy `templates/AnalyticsProvider+Vendor.swift`. Leave the SDK calls commented until the user adds the package, and name the file `AnalyticsProvider+<Vendor>.swift`.
   - For every `// >>> option:<name>` … `// <<< option:<name>` block in the copied files and the Package snippet, keep the contents if the option is selected (delete only the markers). Otherwise delete the whole block.
4. **Tests:** copy `templates/Tests/AnalyticsTests.swift` → `Modules/Tests/AnalyticsTests/`. Delete the sanitizer test if that option isn't selected.
5. **Package.swift:** merge `templates/Package.snippet.swift`. Then add `AnalyticsTests` to the test plan with `python3 .github/skills/ios-project-bootstrap/scripts/sync_test_plan.py <Root>/<App>.xctestplan`. If the plan doesn't exist yet, the script says so. Create it with ios-project-bootstrap's `wire_xcode_project.py` (step 9).
6. **Per-feature events.** For each feature that tracks:
   - Add `.module(.analytics)` to its dependencies and testDependencies.
   - Create `<Feature>Event.swift` from `templates/__Feature__Event.swift`, replacing `__Feature__` and `__feature_snake__` (e.g. `user_profile`).
   - Track from the VM, never from the View.
7. **Screen views.** The feature owns its analytics: track the screen view in the feature VM's `.onAppear` handling (guard against repeats if needed). The coordinator doesn't track on a feature's behalf.
8. **Identity** (option): call `setUserID(pseudonymousID)` after sign-in and `reset()` in the ordered sign-out/reset sequence.

## Naming guidance

- Event names are `snake_case`, `<object>_<action>` in the past tense, at most 40 characters: `item_added`, `sign_in_failed`, `screen_viewed`. Prefix them with the feature (`profile_…`) when the object is ambiguous.
- Parameter keys are `snake_case` nouns. Values are `AnalyticsValue` (string/int/double/bool). Send durations as `duration_ms` Int.
- Send **categories, not text**: `error_category: "network"`, not `error.localizedDescription`. If text is unavoidable, run it through `AnalyticsSanitizer`.
- **No PII:** no emails, names, phone numbers, addresses, free-text input or raw ids from the user's world.
- Invalid names still send, but `reportIssue` fires. That's a purple runtime warning in debug and a failure in tests.

## Rules / Checklist

- Features import `Analytics` only for `TrackingEvent` and `\.analytics`. Only the Analytics target imports vendor SDKs.
- `TrackingEvent` refines `Sendable`, so feature event enums stay nonisolated in MainActor-default modules (SE-0466). Don't add `@MainActor`.
- `track` is sync fire-and-forget, and providers must not block. If an SDK is main-thread-only, hop inside the provider.
- `testValue` is unimplemented. Tests stub `$0.analytics.track` and assert the captured event names/parameters with `LockIsolated`.
- Every event enum switches exhaustively (no `default:`).

## Done criteria

- Only the selected option code remains, and `grep -rn ">>> option\|<<< option" Modules/Sources/Analytics Modules/Package.swift` returns nothing.
- No `__Feature__`/`__feature_snake__` placeholders remain in feature event files.
- At least one feature tracks an event and has a test asserting it.
- **Don't run `xcodebuild`** unless asked.
