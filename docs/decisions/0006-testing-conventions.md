# 0006 — Testing conventions (Swift Testing, dependency overrides, no sleeps)

- **Status:** Accepted
- **Scope:** All test targets

## Context and problem

Tests are only valuable if they're readable, deterministic and fail for the right reason. Common failure modes:
- `Task.sleep` waits that are flaky on CI;
- shared `makeSUT` factories that hide the setup each test depends on;
- no-op test doubles that let unexpected calls pass;
- names that don't say what behaviour is protected.

## Decision

1. **Swift Testing only** (`import Testing`, `@Test`, `#expect`, `#require`). No XCTest for new code.
2. **Naming.** The display name is a Given/When/Then sentence, and the function name is short camelCase:
   ```swift
   @Test("""
       Given the client fails,
       When the view appears,
       Then an error message is shown
       """)
   func onAppearFailureShowsError() async { … }
   ```
3. **Suites for MainActor code are `@MainActor struct XxxTests`.** Suites for nonisolated clients are plain structs.
4. **Dependencies:**
   - A private file-level `makeDependencies(_ d: inout DependencyValues)` sets the suite's **safe shared defaults**, e.g. logger no-ops.
   - Each test adds only the overrides it asserts on:
     `withDependencies { makeDependencies(&$0); $0.x.load = { … } } operation: { XxxViewModel() }`.
   - **No `makeSUT`.** Construction is visible in each test.
   - Unstubbed endpoints stay unimplemented and fail the test (ADR 0004).
5. **No `Task.sleep` in tests.** Wait deterministically:
   - `await sut.loadTask?.value` for stored VM tasks (ADR 0005);
   - `AsyncStream` gates (`let (gate, open) = AsyncStream<Void>.makeStream()`) to hold a stub mid-flight and release it on demand;
   - `ImmediateClock()` (swift-clocks, re-exported by Dependencies) for code that sleeps or retries;
   - `await Task.yield()` only as a last resort, and never as a timing assumption.
6. **Capturing:** use a local `var events` for MainActor `onEvent` closures, and `LockIsolated` (re-exported by Dependencies) inside `@Sendable` stubs.
7. **What to test:**
   - VM: every output event, and each effect's success, failure, cancellation and stale-result paths.
   - StateMaker: pure input → state cases.
   - Coordinator: route → screen, output → navigation, entry effects and reset order.
   - Clients: the live logic against sandboxed backends (pure builders, injected closures). Never the real network or keychain.
8. **No TDD mandate.** Tests ship with the behaviour change in the same PR.
9. **Test helpers stay local** until two test targets need the same one; then move it to a reviewed `TestSupport` module (R15).

## Consequences

- ✅ Tests read as specifications, and failures point at the broken behaviour.
- ✅ No timing flakiness. Races are reproduced with gates, not delays.
- ⚠️ Localized strings in state: compare against `L10n.*` or state defaults, not literals.
- ⚠️ Some small helpers get duplicated across test targets. That's acceptable to avoid a grab-bag module.

## Alternatives considered

- **XCTest.** It's legacy style, with no parameterized tests or traits. Rejected for new code.
- **`makeSUT` factories.** They hide per-test setup and grow flags over time. Rejected.
- **The `.dependencies` test traits** (product `DependenciesTestSupport` of swift-dependencies; verified in `Sources/DependenciesTestSupport/TestTrait.swift`). Not adopted yet; try it on one suite first.
  - `@Suite(.dependencies)` isolates each test's dependencies (fresh `DependencyValues`), useful for parallel tests.
  - `@Test(.dependency(\.uuid, .incrementing))` overrides one key; `@Test(.dependencies { $0.x = … })` overrides several.
  - Swift ≥ 6.1 is needed to write closures inside the macro (older compilers crash; see swiftlang/swift#76409).
  - The VM must still be created inside the scope: traits wrap the whole test, so `let sut = __Feature__ViewModel()` in the body picks them up and `withDependencies` nesting disappears.

## More information

- Templates: `skills/ios-feature-module/templates/Tests/`, and each client skill's `templates/Tests/`.
- Universal takeaway: a test must **own its setup and its clock**. Anything implicit (shared factories, real time) eventually makes it lie.
