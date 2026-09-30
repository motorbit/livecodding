# Task Board — Implementation plan (from docs/SPEC.md, 2026-09-30)

## Modules

| Module | Kind | Depends on | Skill | Options |
|---|---|---|---|---|
| `AppCoordinator` | UI | `BootstrapFeature`, `TaskBoardFeature`, `Logging` | ios-coordinator-route | Bootstrap completion routes to Task Board |
| `BootstrapFeature` | UI | `DesignSystem`, `L10n`, `Logging` | existing module | Keep as startup hook |
| `TaskBoardFeature` | UI | `TaskClient`, `AddTaskFeature`, `TaskDetailFeature`, `DesignSystem`, `L10n`, `Logging` | ios-feature-module | effect: yes; host for add sheet and detail push |
| `AddTaskFeature` | UI | `TaskClient`, `DesignSystem`, `L10n`, `Logging` | ios-feature-module | effect: yes; sheet child |
| `TaskDetailFeature` | UI | `TaskClient`, `DesignSystem`, `L10n`, `Logging` | ios-feature-module | effect: yes; push child |
| `TaskClient` | client | Swift `Dependencies` product | ios-dependency-client | in-memory actor-backed async CRUD mock |
| `DesignSystem` | UI | — | existing module | asset colors, system typography, spacing/radius tokens, components |
| `Logging` | client | Swift `Dependencies` and `DependenciesMacros` products | existing module | Existing logger |
| `L10n` | leaf | — | existing module | Add Task Board, Add Task, and Task Detail accessors/catalog entries |
| `NetworkClient` | client | Swift `Dependencies` product | existing module | Retain from scaffold; not used by the mock TaskClient |

Remove the unused scaffold `HomeFeature` source/test targets and replace the `.home` coordinator route with `.taskBoard`. Keep Bootstrap as the initial route and route `.finished` to `.taskBoard`. The app and package deployment minimum is iOS 17.0; UI state observation follows the existing Combine `ObservableObject` / `@Published` pattern.

## Client contracts

### TaskClient (module `TaskClient`)

```swift
public enum TaskPriority: String, CaseIterable, Codable, Equatable, Sendable {
    case low, medium, high
}

public struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var notes: String
    public var priority: TaskPriority
    public var isComplete: Bool
}

public struct TaskDraft: Equatable, Sendable {
    public var title: String
    public var notes: String
    public var priority: TaskPriority
}

@DependencyClient
public struct TaskClient: Sendable {
    public var fetchTasks: @Sendable () async throws -> [TaskItem]
    public var createTask: @Sendable (_ draft: TaskDraft) async throws -> TaskItem
    public var updateTask: @Sendable (_ task: TaskItem) async throws -> TaskItem
    public var deleteTask: @Sendable (_ id: UUID) async throws -> Void
}
```

- `liveValue`: seeded, in-memory actor-backed implementation. Preserve insertion order and generate UUIDs for new tasks.
- `previewValue`: deterministic four challenge examples.
- `testValue`: unimplemented `Self()`.
- Reads wait 300–800 ms and can fail; all writes are async and can fail. Every operation fails with approximately 15% probability. Inject delay and failure policy into the service factory for deterministic tests; tests must not sleep or access the network.
- Errors are typed and contain no task text. Client tests cover seed values, ordered CRUD, delay/failure injection, and error propagation.
- `TaskClient` does not depend on the pre-existing `NetworkClient`.

## Routes and output contracts

| Route / host route | Owner | Output/action |
|---|---|---|
| `.bootstrap` | `AppCoordinator` | `.finished` → navigate to `.taskBoard` |
| `.taskBoard` | `AppCoordinator` | Creates `TaskBoardViewModel`; list and its child navigation remain owned by the feature |
| `.detail(id: UUID)` | `TaskBoardFeature` host stack | Creates/stores `TaskDetailViewModel` for the selected task |
| Add sheet | `TaskBoardFeature` | `.created(TaskItem)` appends after success; `.closeRequested` dismisses |
| Detail push | `TaskBoardFeature` | `.updated(TaskItem)` replaces the matching row; `.deleted(UUID)` removes it and pops |

The Task Board feature's host stack owns `[TaskBoardRoute]`, the detail VM and the add VM. Child features never import `AppCoordinator` or call each other's `trigger`. Dirty-detail Back asks before discarding; implement a host-owned path-change/confirmation flow that does not mutate the child VM from its parent. Do not add root-owned navigation state or deep links.

## Task DAG and waves

| Wave | Task | Depends on | Parallelism |
|---|---|---|---|
| 0 | Preflight / iOS 17 observation alignment | User choice | Complete; committed as `6c1ffd7` |
| 1 | Confirmed `docs/SPEC.md` | Grill decisions | Complete |
| 2 | Confirm this plan | Spec | Await user checkpoint |
| 3 | Bootstrap / baseline | Plan approval | Existing modular shell; iOS 17 settings aligned |
| 4 | `TaskClient` contract + module/test targets + feature placeholders | Plan approval | Orchestrator only; shared `Package.swift` and test plan |
| 5A | `TaskClient` live mock + client tests | Wave 4 contract | Parallel with 5B |
| 5B | `AddTaskFeature` + `TaskDetailFeature` | Wave 4 contract, `TaskClient` interface | Parallel with 5A and each other; disjoint source/test/L10n accessor files |
| 5C | `TaskBoardFeature` | Wave 5A and 5B | After its host/child APIs are implemented |
| 6 | Coordinator route, localization catalog merge, module map, README/test-plan integration | Wave 5C | Orchestrator only |
| 7 | Review and surgical fixes | Wave 6 | One review per module; fixes/builds serial |

## Worker assignments

| Worker | Allowed paths | Skill |
|---|---|---|
| `task-client-worker` | `Modules/Sources/TaskClient/**`, `Modules/Tests/TaskClientTests/**` | ios-dependency-client |
| `add-task-worker` | `Modules/Sources/AddTaskFeature/**`, `Modules/Tests/AddTaskFeatureTests/**`, `Modules/Sources/L10n/L10n+AddTask.swift` | ios-feature-module |
| `task-detail-worker` | `Modules/Sources/TaskDetailFeature/**`, `Modules/Tests/TaskDetailFeatureTests/**`, `Modules/Sources/L10n/L10n+TaskDetail.swift` | ios-feature-module |
| `task-board-worker` | `Modules/Sources/TaskBoardFeature/**`, `Modules/Tests/TaskBoardFeatureTests/**`, `Modules/Sources/L10n/L10n+TaskBoard.swift` | ios-feature-module |

Workers never edit `Package.swift`, `Localizable.xcstrings`, `L10n.swift`, `AppCoordinator/**`, the project file, shared test plan, or another module. Builds, test-plan changes, catalog merging, integration and commits stay with the orchestrator.

## Build and commit gates

- After contract scaffolding: `cd Modules && swift build --build-tests --triple arm64-apple-ios17.0-simulator`.
- After each worker: same package build, serially. Never run builds concurrently because they share `.build`.
- Integration: `xcodebuild -scheme livecodding -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -quiet build-for-testing`, followed by `test-without-building`; full package tests run on the iOS 27 simulator.
- Configure the app for iPhone-only, portrait-only in the sanctioned Xcode wiring script; do not hand-edit `project.pbxproj`.
- Local commits per autopilot phase/module, with the required Copilot co-author trailer. No push or history rewrite.

## Localization keys

Workers return exact keys and base English values for their `L10n+<Feature>.swift` accessors. The orchestrator merges the catalog after implementation. The key families cover:

- `taskBoard.*`: title, add, loading, empty title/message, load error/retry, completion actions, priority labels and row accessibility.
- `addTask.*`: title, title/notes/priority fields, save/cancel, validation and save error/retry.
- `taskDetail.*`: navigation title, fields, save/delete, delete confirmation, discard confirmation and inline save/delete errors.
- Reuse existing common cancel/retry/error strings when they match; do not duplicate keys.
