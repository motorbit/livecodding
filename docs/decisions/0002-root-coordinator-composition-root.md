# 0002 — Root coordinator as the composition root (pure `makeScreen` + `didEnter`)

- **Status:** Accepted
- **Scope:** Top-level navigation, object graph

## Context and problem

Someone has to create the feature ViewModels, connect their outputs to navigation, and decide what happens on route entry (analytics, resets). If features navigate themselves, they must import each other, which creates cycles and hidden coupling. If the factory that creates screens also runs side effects, then "create a screen" and "entering a screen" become indistinguishable. Tests and previews that only *build* a screen then trigger analytics or network calls.

## Decision

1. `AppCoordinator` is an `@Observable final class` in its own module, and it's the **composition root**. It's the only module that imports every top-level feature.
2. State:
   - `enum AppRoute: Equatable, Sendable` is a *value* describing where to go. It carries ids and context, never loaded data.
   - `enum AppScreen` has one case per route and carries the **live ViewModel**, e.g. `case home(HomeViewModel)`. The VM lives exactly as long as the screen.
   - `var screen: AppScreen?`. It's `nil` only during `init`, so `makeScreen` can capture `[weak self]`.
3. There's a single entry point, `navigate(to:)`: `screen = makeScreen(for: route)`, then `didEnter(route)`.
4. `makeScreen(for:)` is a **pure factory**:
   - It creates the VM with `withDependencies(from: self) { XxxViewModel(...) }`.
   - It sets `vm.onEvent = { [weak self] in self?.handle($0) }` and returns the screen.
   - It doesn't track, fetch, start a `Task` or trigger the VM.
5. `didEnter(_ route:)` holds **app-level route-entry policy** only: session/inactivity timers, resets, pending deep-link flush. It's an exhaustive switch with explicit `break`s. **A feature owns its own logging and analytics, including screen views** (in its VM, e.g. on `.onAppear`); the coordinator never logs on a feature's behalf.
6. **Data loading belongs to the feature VM** (`trigger(.onAppear)` from its View), not to the coordinator.
7. `handle(_ event: XxxViewModelEvent)` has one overload per feature. It maps every output case to `navigate(to:)`, to coordinator state or to an explicit `break`.
8. `CoordinatorView` switches over `screen` and renders the feature View. App-wide overlays (lock, banners, debug menu) are optional coordinator state layered in a `ZStack`. They aren't routes.
9. Global resets (sign-out, environment switch) are **one ordered coordinator method** that cancels work, clears state and then calls `navigate(to:)`.

## Consequences

- ✅ Features are independent and testable. They only emit intents.
- ✅ Building a screen has no side effects, so coordinator tests can assert pure wiring and entry effects separately.
- ✅ Every route touches six places (`AppRoute`, `AppScreen`, `makeScreen`, `didEnter`, `handle`, `CoordinatorView`), and exhaustive switches make a forgotten one a compile error.
- ⚠️ The coordinator grows with the number of top-level routes. Split it into sub-coordinators only when a flow has its own multi-screen lifecycle.
- ⚠️ Navigation *inside* a feature is only partly decided: a host feature may own a host-scoped `NavigationStack` for pushes (`ios-feature-module` ▸ Push presentation); the coordinator never owns one. Deep state from the root is **not decided yet**. See README ▸ Open questions.

## Alternatives considered

- **Features navigate via a shared router/`NavigationPath`.** Features would need to know about each other's routes. Rejected.
- **The coordinator fetches data before showing a screen.** Loading and error UI would then be split between two owners. Rejected: the VM owns loading.
- **Side effects inside `makeScreen`.** It's convenient, but untestable and surprising. Rejected: use `didEnter`.

## More information

- Skills: `ios-coordinator-route`, `ios-project-bootstrap`.
- Universal takeaway: **separate "construct" from "enter"**. Factories wire the graph, and lifecycle hooks run effects. Each is testable on its own.
