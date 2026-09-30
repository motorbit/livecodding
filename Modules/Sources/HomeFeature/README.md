# HomeFeature

The starter landing screen displayed after bootstrap. Replace its title and content when the app's product purpose is defined.

## Public API

| Type | Role |
|---|---|
| `HomeView` | Renders `HomeViewModel.state` and forwards `HomeViewEvent`s |
| `HomeViewModel` | All logic; `trigger(_:)` in, `onEvent` out |
| `HomeViewState` | Display-ready data |
| `HomeViewModelEvent` | Output intents handled by the parent |

## Owner and wiring

- Created by: `AppCoordinator.makeScreen(.home)`.
- Output handled by: `AppCoordinator.handle(_: HomeViewModelEvent)`.
- Dependencies: `DesignSystem`, `L10n`, and `Logging`.

## Flows, races and gotchas

This screen is static and currently emits `.closeRequested`; the root coordinator intentionally treats that event as a no-op.
