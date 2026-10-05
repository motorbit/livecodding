# DebugMenuFeature

Developer tools sheet for debug and non-prod builds. Right now it switches the backend environment (`local` mock, `dev` Go backend, `prod`).

## Public API

| Type | Role |
|---|---|
| `DebugMenuView` | Sheet with the environment list and a Close button |
| `DebugMenuViewModel` | Builds rows from `\.environmentClient`; `trigger(_:)` in, `onEvent` out |
| `DebugMenuViewState`, `DebugMenuEnvironmentRow` | Title, header/footer, rows (name, backend detail, selected) |
| `DebugMenuViewModelEvent` | `.environmentChangeRequested(AppEnvironment)`, `.closeRequested` |
| `DebugMenuButton`, `DebugMenuButtonState` | Floating 🐞 button that opens the menu |

## Owner and wiring

- Opened by: the floating `DebugMenuButton` that `CoordinatorView` layers bottom-left above every screen → `coordinator.openDebugMenu()`. The coordinator creates the button only when `selectableEnvironments()` isn't empty, so never in a prod release build.
- Presented as an overlay sheet over any screen (`AppCoordinator.debugMenu`), not a route.
- Output handled by: `AppCoordinator`. A change request runs the ordered reset `switchEnvironment(to:)`: save the override, drop the screen (cancels in-flight work), start again from `.bootstrap`.
- Dependencies: `AppEnvironment`, `Logging`, `DesignSystem`, `L10n`.

## Gotchas

- Selecting the active environment just closes the menu.
- The button sits under a screen's own sheets and alerts, so it can't open the menu while another modal is up.
