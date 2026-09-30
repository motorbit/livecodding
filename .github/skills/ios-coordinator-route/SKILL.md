---
name: ios-coordinator-route
description: Adds or changes a top-level route in the root AppCoordinator (the composition root). It covers the AppRoute and AppScreen cases, the pure makeScreen wiring, didEnter route-entry effects, handling the feature's onEvent by navigating, the CoordinatorView branch and tests. Use when the user says "add a route", "navigate to X from Y", "wire the feature into the coordinator", "handle event in coordinator" or "on entering screen do X".
---

# iOS coordinator route

## Purpose

This skill wires a feature module into `Modules/Sources/AppCoordinator/`, following ADR 0002. The coordinator is a `@Observable` object that holds `screen: AppScreen?` (one live VM per case). Its only entry point is `navigate(to:)`:

```
navigate(to: route) → screen = makeScreen(for: route)   // pure: create VM + wire onEvent
                     → didEnter(route)                   // route-entry side effects
```

## Inputs / Options

| Option | Values | Default |
|---|---|---|
| Feature | existing `__Feature__Feature` module | required |
| Route case | `case __feature__` or with context, e.g. `case detail(id: Item.ID)` | `__feature__` |
| Entry effects | none / app-level policy (start/stop session timer, reset, flush pending deep link) | none |
| Outputs → routes | mapping of every `__Feature__ViewModelEvent` case → action | ask for unmapped cases |

If the feature's output events aren't mapped, ask: "For each output event of `__Feature__`, what should the coordinator do? [navigate to …] [ignore (explicit break)] [other]".

## Decide first: route, embed or present?

| The screen… | Do this |
|---|---|
| replaces the whole screen (login → home, onboarding → main) | **Top-level route** (this skill) |
| is part of another screen's layout (a tab, a section, a card) | **Embed**: the host feature imports it and owns the child VM (ios-feature-module ▸ Child presentation) |
| is a modal flow that belongs to one host (a picker or detail sheet) | **Present from the host** via an optional child VM in host state |
| is pushed from another feature | Not a route. Use `ios-feature-module` ▸ Push presentation (host-scoped NavigationStack) |

A feature may import another feature **only to embed or present it**. Cross-feature *routing* always goes up through `onEvent` to the coordinator.

## Steps

1. **Package.swift**: add `.module(.__feature__Feature)` to the `appCoordinator` target's dependencies.
2. **AppRoute.swift**: add the case. Routes carry identity and context (ids, modes), never loaded data. They stay `Equatable, Sendable`.
3. **AppScreen.swift**: add `case __feature__(__Feature__ViewModel)` and `import __Feature__Feature`.
4. **AppCoordinator.swift → `makeScreen(for:)`**: add a branch that only creates and wires the VM:
   ```swift
   case .__feature__:
       let viewModel = withDependencies(from: self) { __Feature__ViewModel() }
       viewModel.onEvent = { [weak self] event in self?.handle(event) }
       return .__feature__(viewModel)
   ```
   For route context, pass it through state:
   - `__Feature__ViewModel(state: __Feature__StateMaker.make(.init(id: id)))`, or
   - a VM `init(state:)` default fed by the route.

   Don't `trigger` the VM, don't start a `Task`, and don't track or fetch anything here.
5. **`didEnter(_:)`**: add the case, even if it's `break`, because the switch is exhaustive and has no `default:`. Put app-level route-entry policy here: session timers, resets, pending deep-link flush. **Not** screen-view analytics or feature logging: the feature VM owns those. The effects must be synchronous or start their own stored/fire-and-forget work that doesn't touch the new VM's state.
6. **`handle(_ event: __Feature__ViewModelEvent)`**: add one overload per feature event type, and switch over every case. Map each case to `navigate(to:)`, to coordinator state changes, or to an explicit `break` with a comment.
7. **CoordinatorView.swift**: add `case .__feature__(let viewModel): __Feature__View(viewModel: viewModel)`. Keep the View logic-free.
8. **Tests** (`Modules/Tests/AppCoordinatorTests/`): add
   - one test that `navigate(to: .__feature__)` produces the `.__feature__` screen, and
   - one test per mapped output event. Get the VM from `screen`, call its `onEvent?(…)` directly to simulate the child, and assert the new `screen`.
   - One test per entry effect, asserting it on a stubbed client with `LockIsolated`.

   Pattern-match screens with `guard case .__feature__(let vm)? = sut.screen else { Issue.record(); return }`.

## Rules / Checklist

- `makeScreen` is **pure**: it creates the VM with `withDependencies(from: self)`, wires `onEvent` with `[weak self]`, and returns. Nothing else happens there.
- Data loading belongs to the feature VM (`trigger(.onAppear)` from its View), not to the coordinator.
- `didEnter` and `handle` list every case. Don't use `default:`.
- Features never import `AppCoordinator`. The coordinator doesn't reach into VM internals. It calls neither `trigger` nor state setters.
- Overlays (lock screen, banners, debug menu) are optional coordinator state rendered in the `ZStack`. They aren't routes.
- Global resets (environment switch, logout) go through one ordered coordinator method, e.g. `resetSession()`, which cancels work, clears clients and then calls `navigate(to:)`.

## Done criteria

- `AppRoute`, `AppScreen`, `makeScreen`, `didEnter`, `handle` and `CoordinatorView` all include the new case. Grep for the case name and check that it appears in all six places.
- The AppCoordinator target depends on the feature module.
- Coordinator tests cover the navigation, every mapped output and every entry effect.
- **Don't run `xcodebuild`** unless asked.
