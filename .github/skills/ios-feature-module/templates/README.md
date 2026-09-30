# __Feature__Feature

<!-- One paragraph: what the user can do on this screen and why it exists. -->

## Public API

| Type | Role |
|---|---|
| `__Feature__View` | Renders `__Feature__ViewModel.state` and forwards `__Feature__ViewEvent`s |
| `__Feature__ViewModel` | All logic; `trigger(_:)` in, `onEvent` out |
| `__Feature__ViewState` | Display-ready data |
| `__Feature__ViewModelEvent` | Output intents handled by the parent |

## Owner and wiring

- Created by: `AppCoordinator.makeScreen(.__feature__)` / `<HostFeature>` (embedded child).
- Output handled by: `<parent>.handle(_: __Feature__ViewModelEvent)`.
- Dependencies: `<clients>`.

## Flows, races and gotchas

<!-- Loading/retry behaviour, what cancels what, generation guards, anything non-obvious. -->
