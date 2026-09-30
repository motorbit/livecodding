# BootstrapFeature

The app's first screen. It shows a progress indicator while start-up work runs, then asks the coordinator to show the first real screen. Right now it does nothing and finishes immediately. It's the hook for longer setup: restoring a session, fetching remote config, running migrations or checking for a forced update.

## Public API

| Type | Role |
|---|---|
| `BootstrapView` | Full-screen progress indicator; sends `.onAppear` |
| `BootstrapViewModel` | Runs start-up work; `trigger(_:)` in, `onEvent` out |
| `BootstrapViewState` | The accessibility label for the indicator |
| `BootstrapViewModelEvent` | `.finished` (add intents such as `loginRequired` as needed) |

## Owner and wiring

- Created by: `AppCoordinator.makeScreen(.bootstrap)`. `.bootstrap` is the default initial route.
- Output handled by: `AppCoordinator.handle(_: BootstrapViewModelEvent)`. `.finished` navigates to `.home`.
- Dependencies: `Logging`, `DesignSystem`, `L10n`.

## Adding a start-up step

1. Wrap the service in a client (**ios-dependency-client**) and add its module to this target's `dependencies` and `testDependencies`.
2. Declare it at class level (`@Dependency`), read it before the Task starts in `runSetup()`, and `await` it inside the Task.
3. Map the outcome to an `InternalAction`. For a branching outcome, add a `BootstrapViewModelEvent` case and map it in the coordinator.
4. If the step can fail, add error state plus a retry `ViewEvent`, and let retry restart `runSetup()`.
5. Add tests with a stubbed client.

## Flows, races and gotchas

- `.onAppear` starts setup only once per VM (`setupTask == nil`). The coordinator creates a fresh VM each time `.bootstrap` is entered.
- The Task is cancelled in `deinit`. The generation guard drops results from a superseded run.
- Keep this screen short. Anything that can run after the first screen appears belongs in that screen's VM.
