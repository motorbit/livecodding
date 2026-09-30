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
| `NetworkClient` | client | Swift `Dependencies` product | existing module | Retained as scaffold for a future real backend; unused |

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
| 2 | Confirm this plan | Spec | Approved by user |
| 3 | Bootstrap / baseline | Plan approval | Existing modular shell; iOS 17 and iPhone portrait settings aligned |
| 4 | `TaskClient` contract + module/test targets + feature placeholders | Plan approval | Complete; orchestrator owns shared `Package.swift` and test plan |
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
- App is configured for iPhone-only, portrait-only through the sanctioned Xcode wiring script; do not hand-edit `project.pbxproj`.
- Local commits per autopilot phase/module, with the required Copilot co-author trailer. No push or history rewrite.

## Localization keys

Workers return exact keys and base English values for their `L10n+<Feature>.swift` accessors. The orchestrator merges the catalog after implementation. The key families cover:

- `taskBoard.*`: title, add, loading, empty title/message, load error/retry, completion actions, priority labels and row accessibility.
- `addTask.*`: title, title/notes/priority fields, save/cancel, validation and save error/retry.
- `taskDetail.*`: navigation title, fields, save/delete, delete confirmation, discard confirmation and inline save/delete errors.
- Reuse existing common cancel/retry/error strings when they match; do not duplicate keys.

---

# Phase 2 — Challenge alignment plan (2026-09-30)

Source: the review of the project against the challenge brief, plus spec revision R1–R6. Each step is one local commit; don't push. Mark items done as you go.

## Dependency changes

| Module | Change |
|---|---|
| `TaskClient` | Adds `resources: [.process("Resources")]` for `seed-tasks.json`; no new module dependencies |
| `HomeFeature` | Removed (source, tests, `Module` case, `uiModule` entry) |
| `TaskBoardFeature` | No new modules; uses `\.continuousClock`, `\.date`, `\.calendar`, `\.locale` |
| `AddTaskFeature`, `TaskDetailFeature` | No new modules |

## Steps

### 1. ✅ Cleanup — `chore: remove unused HomeFeature`
- Delete `Sources/HomeFeature`, `Tests/HomeFeatureTests`, the `.homeFeature` case and its `uiModule(...)` block in `Package.swift`.
- Delete the empty `Tests/AddTaskFeatureTests/AddTaskFeatureTests.swift`.
- `python3 .github/skills/ios-project-bootstrap/scripts/sync_test_plan.py Livecodding.xctestplan --prune`.
- Gate: package builds.

### 2. ✅ Model + DTOs — `feat(TaskClient): add due date and DTO mapping`
- `TaskItem.dueDate: Date?` (a calendar day, stored at start of day in UTC); `TaskDraft.dueDate: Date?`.
- `TaskDTO` / `TaskDraftDTO` (Codable, snake_case keys, `"Low"|"Medium"|"High"` priority, `done`, `due_date` as `yyyy-MM-dd`) with `init(_ item:)` / `toDomain()`.
- `TaskClientError`: `.validation`, `.notFound`, `.unavailable` (drop `.simulatedFailure`; 503 → `.unavailable`).
- Tests: DTO round-trip, priority string mapping, date-only encoding, decoding the verbatim challenge JSON.

### 3. ✅ Mock network layer + repository — `feat(TaskClient): add mock network layer`
- `TaskNetworkClient` (`@DependencyClient`, internal): DTO-level CRUD, throws `TaskNetworkError` (`.badRequest`, `.notFound`, `.serverError`). `liveValue = .mock(policy: .live)` (the single swap point for a real backend), `previewValue = .mock(policy: .instant)`, `testValue` unimplemented.
- `MockNetworkPolicy`: `readDelay` 300–800 ms, `writeDelay` 100–300 ms, `wait`, `shouldFail` (15 %); `.instant` for previews/tests.
- `actor MockNetworkClient`: seeds from `Resources/seed-tasks.json` (verbatim challenge JSON) with stable IDs `…0001`–`…0004`; assigns IDs, trims and validates titles, throws `.notFound`.
- `TaskClient.repository` (live + preview): resolves `\.taskNetworkClient` per call; DTO ↔ domain; `TaskNetworkError` → `TaskClientError`; `CancellationError` passes through. The old `InMemoryTaskService` is deleted.
- Tests: seeds == `TaskItem.samples`, read vs write delays, CRUD order/normalization, 400/404-style errors, failures don't mutate; repository round-trip, error mapping, malformed response, cancellation.

### 4. ~~Repository over NetworkClient~~ — merged into step 3.

### 5. Async refresh — `feat(TaskBoardFeature): await pull-to-refresh`
- `public func refresh() async { trigger(.refreshRequested); await loadTask?.value }`; the View uses `.refreshable { await viewModel.refresh() }`.
- Remove `.refreshRequested` from the View's direct use (it stays internal to `refresh()`).
- ADR 0003: add an "Exception: async refresh for `.refreshable`" note; AGENTS.md R7: add one line referencing it.
- Tests: `refresh()` returns only after the load is handled; a superseded load still resolves.

### 6. List + swipe-delete with undo — `feat(TaskBoardFeature): swipe to delete with undo`
- Switch `ScrollView/LazyVStack` to `List` (plain style, DS row insets, separators matching `DSDivider`).
- `.swipeActions(edge: .trailing) { Button(role: .destructive) → .deleteSwiped(id) }`.
- VM: `pendingDeletion: (item, index, generation)?`, `undoTask` using `@Dependency(\.continuousClock)`, sleeping 4 s → `.commitDeletion`. Events: `.deleteSwiped`, `.undoTapped`, `.deleteRetryTapped(id)`. A second swipe commits the previous one first. Reloads filter the pending id. Failure restores the row at its index with `rowErrorMessage` and Retry (generalize `completionErrorMessage` into a row error + retry kind).
- State: `undoBanner: UndoBannerState?` (message + button title from L10n).
- Tests (`TestClock`): undo within the window → no delete call; expiry → delete once; failure → restored with error; retry; second swipe commits the first; reload while pending.

### 7. Search + sort — `feat(TaskBoardFeature): search and sort`
- Events `.searchTextChanged(String)` and `.sortChanged(TaskSortOrder)`; `TaskSortOrder: CaseIterable { case default, priority, status }` in the feature.
- `rebuildRows()` = stable-sort by order → filter by the normalized query (`localizedStandardContains` after trim).
- `phase` remains data-driven; the new `isNoResults` flag / "No matching tasks" view appears when tasks exist but none match.
- View: `.searchable(text: Binding(get: state.searchText, set: trigger))`, toolbar `Menu` with a `Picker` over `state.sortOptions` (labels from L10n).
- Tests: filter case/diacritics/trim, each sort with stable ties, search + sort combined, no-results vs empty, interaction with add/delete/complete.

### 8. Due dates — `feat: due dates with relative formatting`
- AddTask and TaskDetail: `hasDueDate` toggle + date-only `DatePicker`; dirty-state comparison includes `dueDate`; the draft carries it.
- Board rows: `dueText: String?`, `isOverdue: Bool`, produced in the VM from `\.date.now`, `\.calendar`, `\.locale`: "Due today", "Due tomorrow", "Due in 3 days", "Overdue by 2 days" (L10n plural/format entries). Completed tasks show plain "Due …" without overdue styling.
- Tests: formatting boundaries (today / tomorrow / yesterday / N days), overdue flag, add/edit/clear due date, dirty detection.

### 9. Docs + gates — `docs: align README, AGENTS and SPEC`
- Update the `TaskClient`, `TaskBoardFeature`, `AddTaskFeature` and `TaskDetailFeature` READMEs. Update the AGENTS.md Module map (TaskClient purpose; `NetworkClient` is unused scaffold).
- Add L10n entries (sort, search, undo, row delete error, due-date strings) to the String Catalog.
- Run package tests + the app build on the iPhone 18 Pro Max simulator (authorized by the SPEC).
- Run the `ios-reviewer` agent on the changed files and fix the ❌ findings.

## Risks / notes
- `List` + `.swipeActions` changes row layout and hit-testing: re-check the 44-pt completion button inside the row (`.buttonStyle(.plain)` prevents whole-row taps).
- The deferred swipe delete is optimistic by design (SPEC R2). The detail delete stays pessimistic.
- Walk-through talking points: why a DTO-level mock network client (one swap point: `TaskNetworkClient.liveValue`; the repository maps DTOs/errors) and why iOS 17 (satisfies 16+).
