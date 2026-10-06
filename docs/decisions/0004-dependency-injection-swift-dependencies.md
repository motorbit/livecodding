# 0004 — Dependency injection with swift-dependencies `@DependencyClient` structs

- **Status:** Accepted
- **Scope:** All clients and their consumers

## Context and problem

ViewModels need network, storage, clocks, logging and analytics. Two common approaches both hurt. Protocol + mock classes per dependency mean lots of boilerplate, and mocks drift from the real API. Singletons can't be overridden in tests and previews. Constructor injection through every layer bloats initializers and conflicts with our parameter-less `ViewModel.init` (ADR 0003). We also need test doubles that **fail loudly** when an unexpected dependency is used.

## Decision

1. Use [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) (≥ 1.9). Each capability is a `@DependencyClient public struct XxxClient: Sendable` of `@Sendable` closures, **not a protocol**.
2. Each client lives in its own **client module**, which is nonisolated (ADR 0005). Never declare a client inside a MainActor-default UI module.
3. Values:
   - `liveValue` lives **in the client module**. The app shell doesn't register anything.
   - `previewValue` holds canned data where previews use the client.
   - `testValue = Self()`, which is the macro's **unimplemented** client. Never write a no-op `testValue`. (If `testValue` is omitted, `withDependencies` overrides are applied on top of `previewValue`, which defaults to `liveValue`. Endpoints a test didn't stub would then silently run real code.)
4. The macro rules: non-throwing endpoints that return a value need a default in the struct. Throwing and `Void` endpoints don't.
5. Consumers declare `@Dependency(\.xxx) private var xxx` **at class level**. Under the `ObservableObject` UI pattern (iOS 17 target) this property is not `@Published`; inside effects, read the client into a local before starting a `Task`.
6. Parents create children with `withDependencies(from: self) { Child() }`, so test overrides propagate down the object graph.
7. **No UseCase/Interactor layer by default.** A VM calls clients directly. Extract a use case only when a **second real consumer** needs the same orchestration.
8. SDK and vendor types never cross a client's API. Endpoints use `Sendable` domain types.

## Consequences

- ✅ Tests override exactly the endpoints they need:
  `withDependencies { makeDependencies(&$0); $0.x.fetch = { … } } operation: { VM() }`.
  Anything unexpected fails the test.
- ✅ Previews get deterministic data with no setup.
- ✅ There's no protocol/mock pair to keep in sync. Adding an endpoint is one line.
- ⚠️ Unimplemented endpoints that return a value need a placeholder default, which is returned after reporting the issue.
- ⚠️ `@Dependency` resolves from task-local context. Code that escapes that context (e.g. an unrelated long-lived object created outside `withDependencies`) sees live values. That's why `withDependencies(from:)` is mandatory for child creation.
- ⚠️ This is a third-party dependency. It's widely used and stable, and the kit uses only its core API.

## Alternatives considered

- **Protocols + hand-written mocks.** Boilerplate, and mocks drift silently. Rejected.
- **Environment values (`@Environment`) for services.** They're only available in Views, not in VMs. Rejected.
- **Constructor injection only.** It conflicts with parameter-less VM `init`, and the parameter lists grow. Rejected.
- **No-op `testValue`.** Tests would pass while calling things they shouldn't. Rejected.

## More information

- Skills: `ios-dependency-client`, plus every client skill.
- Universal takeaway: test doubles should **fail on unexpected use by default**. Opt in to each behaviour a test relies on.
