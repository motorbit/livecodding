# 0003 — MVVM feature contract (View / State / ViewModel)

- **Status:** Accepted
- **Scope:** Every feature module

## Context and problem

SwiftUI makes it easy to put logic in Views: `.task {}` blocks, formatting and `if` on business rules. That logic can't be unit-tested without UI, and it's duplicated between previews and runtime. ViewModels without a contract also drift: public setters, async `trigger`s, several callback closures, and work in `init` that runs whenever a preview or test creates the VM. We want one shape that every feature follows, so any reader and any agent knows where things go.

## Decision

Each feature has these types:

| Type | Shape |
|---|---|
| `XxxView` | `struct: View`. Holds an `@ObservedObject` ViewModel. Renders `viewModel.state` and calls `viewModel.trigger(.event)`. Nothing else. |
| `XxxViewState` | Plain `Equatable` struct. Display-ready values, and strings already localized. No computed logic and no custom `==`. |
| `XxxViewEvent` | Input enum. Only the View sends it. |
| `XxxViewModelEvent` | Output enum (`Equatable`; `Sendable` only if it crosses isolation). The parent handles it. |
| `XxxViewModel` | `ObservableObject public final class` with `@Published public private(set) var state` (MainActor via module default, ADR 0005). All logic lives here. |
| `XxxStateMaker` | *Optional.* It builds the initial state when that needs dependencies or computation: a pure `make(_ input:)` plus a `live()` that reads dependencies. |

ViewModel rules:
1. `public private(set) var state`.
2. `public func trigger(_ event: XxxViewEvent)` is **synchronous**. It starts effects. It never `await`s itself.
   *Exception (pull-to-refresh):* a VM may also expose `public func refresh() async` for SwiftUI `.refreshable`, which must suspend until loading ends. It sends its own refresh event through `trigger`, then only awaits the stored load Task(s). It adds no logic of its own and is the only async entry point allowed. Example: `TaskBoardViewModel.refresh()`.
3. `public var onEvent: ((XxxViewModelEvent) -> Void)?` is the **single output**. It's a plain closure: not `@Sendable`, and no `assumeIsolated`. Parent and child share MainActor.
4. `init(state: XxxViewState = XxxViewState())` (or `= XxxStateMaker.live()`) is the only initializer parameter. It reads no dependencies, starts no work and does no logging.
5. Dependencies are `@Dependency(\.x) private var x` at class level (ADR 0004). Dependencies and stored Tasks are not `@Published`.
6. Effect results come back as `private enum InternalAction`, handled in `private func handle(_ action:)`. That's the only place effect results mutate `state`.
7. Async effects are **stored Tasks** that are cancelled before a restart and guarded by a generation counter (ADR 0005).
8. Parents talk to children only through the child's `onEvent`. They never call a child's `trigger` or mutate its state.
9. There's no `default:` in switches over the project's own enums.

Views format nothing. Where possible, strings are resolved in the VM, the StateMaker or the `State.init` defaults (L10n). Static labels in a View are tolerated.

## Consequences

- ✅ Every behaviour is a unit test: create the VM, `trigger`, assert `state` and the emitted events.
- ✅ Previews construct state directly, with no mocks needed for static screens.
- ✅ `InternalAction` gives async results the same traceable path as user input.
- ⚠️ Slightly more types per feature. The templates generate them.
- ⚠️ Localized strings in state make tests locale-dependent if they compare literal text. Compare against `L10n.*` or the `State()` defaults instead.

## Alternatives considered

- **The Composable Architecture (TCA).** It gives strong guarantees, but it's a heavier framework and learning curve. The kit borrows its ideas (`Destination` enums, DI) but not the runtime.
- **`async func trigger`.** Callers would then decide when effects finish, which puts `Task {}` back into Views. Rejected.
- **Multiple output closures** (`onClose`, `onDone`, …). They're harder to route exhaustively. Rejected in favour of one enum.
- **Generic shared `StateMaker` protocol.** No real benefit over a per-feature enum. Rejected.

## More information

- Skills: `ios-feature-module`. Templates: `skills/ios-feature-module/templates/`.
- Universal takeaway: **one input, one output, one state**. The View is a pure function of state, and every side effect has a named, testable path.
