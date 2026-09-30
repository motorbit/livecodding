# Architecture decisions

Short MADR-style records of the kit's universal decisions. Copy this folder into a new project as `docs/decisions/`, then add project-specific ADRs from `0007` on.

| # | Decision | Enforced by |
|---|---|---|
| [0001](0001-thin-app-shell-local-spm-modules.md) | Thin app shell + one local SPM module per feature | module graph, `ios-project-bootstrap` |
| [0002](0002-root-coordinator-composition-root.md) | Root coordinator is the composition root (pure `makeScreen` + `didEnter`) | `ios-coordinator-route` |
| [0003](0003-mvvm-feature-contract.md) | MVVM contract: View / State / VM, `trigger` / `onEvent`, `InternalAction`, StateMaker | `ios-feature-module` |
| [0004](0004-dependency-injection-swift-dependencies.md) | DI with swift-dependencies; unimplemented `testValue`; no default UseCase layer | `ios-dependency-client` |
| [0005](0005-concurrency-default-isolation-stored-tasks.md) | Swift 6.2 isolation split, `@concurrent`, stored tasks + generations | `Package.swift` settings, templates |
| [0006](0006-testing-conventions.md) | Swift Testing, `makeDependencies` + overrides, no sleeps | test templates |

Format: Status, Context and problem, Decision, Consequences, Alternatives considered, More information (with a "universal takeaway"). Supersede an ADR with a new one instead of editing its decision.
