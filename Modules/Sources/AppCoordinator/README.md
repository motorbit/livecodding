# AppCoordinator

The composition root (ADR 0002). It turns an `AppRoute` into a live `AppScreen`, wires each screen's `onEvent`, and runs route-entry effects. Nothing imports this module; it imports every top-level feature.

## Public API

| Type | Role |
|---|---|
| `AppCoordinator` | `navigate(to:)`, the only navigation entry point; `screen` is the current screen |
| `AppRoute` | Where the app can go (identity/context only, no loaded data) |
| `AppScreen` | The current screen with its live ViewModel |
| `CoordinatorView` | Maps `screen` to a View and layers app-wide overlays |

## Routes

| Route | Screen | Entry effects | Outputs handled |
|---|---|---|---|
| `.bootstrap` (initial) | `BootstrapView` | none | `.finished` → `.taskBoard` |
| `.taskBoard` | `TaskBoardView` | none | none (root screen) |

Keep this table in sync when adding a route (**ios-coordinator-route**).

## Rules

- `makeScreen` is pure: create the VM with `withDependencies(from: self)`, wire `onEvent`, return.
- App-level route-entry policy goes in `didEnter(_:)`. Loading, logging and analytics belong to the feature VM.
- Every `switch` lists every case, with no `default:`.
