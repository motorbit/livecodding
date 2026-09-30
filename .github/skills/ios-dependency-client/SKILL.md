---
name: ios-dependency-client
description: Creates a swift-dependencies `@DependencyClient` struct in its own client module. It includes a liveValue (with @concurrent off-main work), an optional previewValue, an unimplemented testValue, a DependencyValues key, the Package.swift wiring and tests. Use when the user asks to "add a client", "wrap an API/SDK/system service", "add a dependency", "inject X" or "make X testable".
---

# iOS dependency client

## Purpose

This skill wraps one external capability (a system API, SDK, storage, clock or network endpoint group) in a struct of `@Sendable` closures that features can inject and tests can override, following ADR 0004 and ADR 0005.

## Inputs / Options

| Option | Values | Default |
|---|---|---|
| `Name` | UpperCamel capability, e.g. `Location` → `__Name__Client`; lowerCamel `location` → `\.__name__Client` | required |
| Endpoints | list of `name: (args) [async] [throws] -> Result` | ask |
| previewValue | yes (the client is used by views with `#Preview`) / no | yes |
| Shared mutable state in live | none / `Mutex` (sync access) / `actor` (async only) | none |
| Placement | new module (default) / an existing client module that owns the same capability | new module |

If the endpoints aren't given, ask the user to list them. Don't invent an API surface.

## Steps

1. **Design the endpoints.**
   - Each endpoint is `@Sendable`, and its arguments and results are `Sendable` value types.
   - Model domain types in the client module, not as SDK types.
   - Name endpoints as verbs (`fetchProfile`, `save`, `clear`).
2. **Create the module** `Modules/Sources/__Name__Client/`:
   - `__Name__Client.swift` ← `templates/__Name__Client.swift`: the struct, `DependencyKey` and `DependencyValues`.
   - `Live__Name__Client.swift` ← `templates/Live__Name__Client.swift`: `static func live(...)` plus a backing type.
   - `README.md` ← `templates/README.md`.
3. **Default values** (swift-dependencies ≥ 1.9 `@DependencyClient` rules):
   - `async throws` or `throws` endpoints need no default. Unimplemented calls throw and report an issue.
   - Non-throwing endpoints that return a value **require** a default in the struct, e.g. `= { nil }` or `= { false }`.
   - `-> Void` endpoints need no default.
4. **Values:**
   - `liveValue` is the real implementation.
   - `previewValue` is optional canned data.
   - `testValue = Self()`: **always** unimplemented, **never** a no-op struct.
5. **Isolation in the live implementation:**
   - The module is nonisolated (`clientModule`), and the struct is `Sendable`.
   - Async closures run on the caller's actor (`NonisolatedNonsendingByDefault`). Put blocking I/O and CPU work in `@concurrent` functions of the backing type.
   - Protect shared sync state with `Mutex` (import Synchronization), or use an `actor` when all access is async.
   - Never capture UIKit or MainActor objects in live closures. If an SDK requires main, hop explicitly with `await MainActor.run { … }` inside the live implementation.
6. **Package.swift**: merge `templates/Package.snippet.swift`. Add the module to each consumer's `dependencies` and `testDependencies`.
7. **Tests** `Modules/Tests/__Name__ClientTests/` ← `templates/Tests/Live__Name__ClientTests.swift`. Test the live logic against a sandboxed backing (a temp file or an injected closure). Skip this only for thin wrappers with no logic, and set `tests: false`.
   - **Test plan:** if there are tests, run `python3 .github/skills/ios-project-bootstrap/scripts/sync_test_plan.py <Root>/<App>.xctestplan`. If the plan doesn't exist yet, the script says so. Create it with ios-project-bootstrap's `wire_xcode_project.py` (step 9).
8. **Consumers** declare `@Dependency(\.__name__Client) private var __name__Client` at class level (not `@Published` in the iOS 16 `ObservableObject` UI pattern). They read it (`let client = __name__Client`) **before** starting a `Task`.

## Templates

- `templates/__Name__Client.swift`: the struct, key and values.
- `templates/Live__Name__Client.swift`: `live(storage:)`, plus a `Sendable` backing class with `Mutex` and `@concurrent`.
- `templates/Tests/Live__Name__ClientTests.swift`: tests of the live implementation.
- `templates/Package.snippet.swift` and `templates/README.md`.

## How consumers override in tests

```swift
let sut = withDependencies {
    makeDependencies(&$0)                       // suite-wide safe defaults
    $0.__name__Client.load = { "stub" }         // only what this test asserts on
} operation: {
    SomeViewModel()
}
```

Endpoints that aren't overridden stay unimplemented. If the code under test calls one, the test fails, and that's intended. Collect calls from `@Sendable` stubs with `LockIsolated` (re-exported by `Dependencies`).

## Rules / Checklist

- It's a struct of closures, not a protocol. Don't add a UseCase or repository layer unless a **second real consumer** needs shared orchestration.
- `liveValue` lives in the client module. The app target never calls `prepareDependencies` for it.
- Don't declare a `@DependencyClient` inside a MainActor-default (UI) module. Put it in a client module, even if only one feature uses it.
- Don't let SDK or vendor types leak through endpoint signatures.
- Never log secrets, tokens or PII from a live implementation. Use `logger` with metadata. Never `print`.
- Name the `DependencyValues` property `__name__Client`. Name the module and type `__Name__Client`.

## Done criteria

- No `__Name__`/`__name__` placeholders remain.
- `testValue = Self()` is present, and there's no no-op `testValue`.
- Every non-throwing, value-returning endpoint has a default.
- Blocking work in the live implementation is `@concurrent` or runs inside an actor.
- The module is listed in `Package.swift` with `clientModule`, and it's added to its consumers.
- Its test target, if it has one, is in the `.xctestplan` (`sync_test_plan.py`).
- **Don't run `xcodebuild`** unless asked.
