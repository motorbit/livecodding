# 0005 — Concurrency: Swift 6.2 default-isolation split, stored tasks, generations

- **Status:** Accepted
- **Scope:** All modules

## Context and problem

Swift 6 strict concurrency is on. UI code is naturally MainActor, but annotating every View, VM and state type is noise. Swift 6.2 adds per-module **default actor isolation** (SE-0466) and makes nonisolated async functions **run on the caller's actor** (SE-0461, `NonisolatedNonsendingByDefault`). Clients must stay usable from any context. VMs also need a safe pattern for restartable async work: retry, pull-to-refresh, search-as-you-type. Otherwise stale results overwrite fresh ones.

## Decision

1. **Toolchain and deployment:** swift-tools-version 6.2, Swift 6 language mode, minimum iOS 16.0. The Swift 6.2 compiler/toolchain requirement is independent of the deployment target; APIs newer than iOS 16 require availability checks or compatible alternatives.
2. **Isolation split per module** (in `Package.swift`):
   - **UI modules** (features, `AppCoordinator`, `DesignSystem`): `.defaultIsolation(MainActor.self)`.
   - **Client/infrastructure modules** (network, keychain, logging, analytics, environment, L10n): nonisolated default. Their `@DependencyClient` structs are `Sendable`, with `@Sendable` closures.
   - **All modules:** `.enableUpcomingFeature("NonisolatedNonsendingByDefault")` and `.enableUpcomingFeature("InferIsolatedConformances")`. This is Xcode's "Approachable Concurrency" pair, and SE-0470 recommends the latter whenever MainActor inference is on. Test targets mirror the settings of their module.
3. **Off-main work:**
   - Under `NonisolatedNonsendingByDefault`, a nonisolated `async` function or closure runs on the caller's actor. Awaiting I/O suspends and is fine.
   - **CPU-heavy or blocking work** (JSON decoding, SecItem, file I/O) goes in `@concurrent` functions: `@concurrent func decode(...) async throws -> T`.
   - Never use `DispatchQueue` or `MainActor.run` in UI modules, because they're already MainActor.
4. **Restartable effects in VMs:**
   - Store the handle: `var loadTask: Task<Void, Never>?`. **Cancel it before a restart** and in `deinit`.
   - Use a **generation counter** (`loadGeneration += 1; let generation = loadGeneration`) instead of `Bool isLoading` re-entrancy flags.
   - After every `await`: `guard !Task.isCancelled, let self, self.loadGeneration == generation else { return }`.
   - Deliver results through `InternalAction` (ADR 0003).
   - Read dependencies into locals **before** creating the `Task`. Capture `[weak self]`.
5. **Output closures between MainActor objects** (`onEvent`) are plain closures. They aren't `@Sendable` and don't use `assumeIsolated`.
6. `Sendable` only where values cross isolation: client endpoints, events sent to clients and route values. Types that directly conform to a `Sendable`-refining protocol (e.g. `TrackingEvent`) stay nonisolated even in MainActor-default modules (SE-0466).
7. `Task.immediate` (SE-0472, iOS 26+) may be used only behind an iOS 26 availability check; it isn't used by default because the app supports iOS 16.

## Consequences

- ✅ UI code carries almost no annotations, and clients are callable from anywhere.
- ✅ Stale results are dropped deterministically, and tests can `await vm.loadTask?.value`.
- ⚠️ A heavy synchronous call hidden in a client can now run on main. Code review checks for `@concurrent` on CPU-bound paths.
- ⚠️ In MainActor-default modules, `Bundle.module`, static lets and conformances become MainActor-isolated. Keep resource accessors that nonisolated code needs (L10n) in nonisolated modules.

## Alternatives considered

- **MainActor default everywhere.** Clients would then need `nonisolated` on every member. Rejected.
- **No default isolation, annotate UI manually.** It's noisy, and one missing `@MainActor` becomes a diagnostic hunt. Rejected.
- **`Bool` "isLoading" guards.** They block legitimate restarts and don't prevent stale writes. Rejected.

## More information

- SE-0466 (default isolation): https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md
- SE-0461 (nonisolated nonsending, `@concurrent`): https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md
- SE-0470 (isolated conformances): https://github.com/swiftlang/swift-evolution/blob/main/proposals/0470-isolated-conformances.md
- Universal takeaway: make isolation a **module-level decision**, and make "latest wins" explicit with cancellation + generations.
