# Task Board — Spec (confirmed 2026-09-30, revised 2026-09-30 for challenge alignment)

## Goal, users, MVP scope, non-goals

Build a small, polished task board for an individual to track personal tasks during a 60-minute AI-assisted live-coding exercise. The MVP lets the user browse seeded tasks, add a task, view/edit a task, mark it complete, and delete it (from detail, or by swiping in the list with undo). The list demonstrates loading, empty, and error states against a self-built mock network layer. Selected stretch goals: search by title, sort by priority/completion, swipe-to-delete with undo, and due dates with relative formatting.

**Non-goals:** backend or real HTTP integration, authentication, analytics, environment switching, persistence across launches, tabs, UI state restoration, and custom theming beyond the existing light/dark DesignSystem assets. The selected stretch goals are built only after the core flow and all its states work.

## Screens

| Screen | Module | Placement | Data source | States | Outputs |
|---|---|---|---|---|---|
| Task Board list | `TaskBoardFeature` | Initial top-level route after Bootstrap; owns its host-scoped `NavigationStack` | `TaskClient.fetchTasks()` | Initial loading; empty with Add action; load error with Retry; content; no search results; reload error banner while retaining existing content; pending-delete undo banner | Add opens sheet; row tap pushes detail; completion toggle updates through client; swipe deletes with undo; search and sort are local |
| Add task | `AddTaskFeature` | Sheet from `TaskBoardFeature` | `TaskClient.createTask(_:)` | Editable form including optional due date; saving with active controls disabled; inline error with Retry | Success dismisses and appends the new task; failure keeps the sheet and draft |
| Task detail/edit | `TaskDetailFeature` | Push on `TaskBoardFeature`'s `NavigationStack`; route carries task ID only | Task passed from list; `TaskClient.updateTask(_:)` / `deleteTask(id:)` | Editable draft including optional due date; saving; inline retryable error; delete confirmation | Save remains on detail and reports updated task to host; delete success reports ID and pops; Back with unsaved edits asks to discard |

Task rows show title, a Low/Medium/High text badge with a subtle semantic color accent, a completion toggle and, when set, a relative due-date line (e.g. "Due tomorrow", "Overdue by 2 days"; overdue incomplete tasks use the error color plus text, never color alone). Tapping a row (outside the completion control) opens detail. Completed tasks remain visible, checked and visually subdued.

The list is a SwiftUI `List` (needed for `.swipeActions`). Default order is seed/API order: new tasks are appended, and editing or completing doesn't reorder. A toolbar sort menu offers **Default**, **Priority** (High → Low) and **Status** (incomplete first). Ties keep API order. Sorting is local and resets to Default on relaunch.

`.searchable` filters by title: case- and diacritic-insensitive substring, trimmed, applied after sorting. If tasks exist but none match, the list shows a "No matching tasks" state, separate from the empty state. Search and sort never trigger network calls.

**Swipe-to-delete with undo** is a deliberate exception to pessimistic mutations. A trailing swipe hides the row at once and shows an undo banner for 4 s, timed by an injected clock. Undo restores the row with no request. When the window expires, `deleteTask` is sent. On failure the row is restored in its original position with an inline row error and Retry. Only one delete is pending at a time: a second swipe commits the first immediately. Reloads keep pending rows hidden. Delete from detail keeps the confirmation and stays pessimistic.

The list has a Task Board title and an Add action. The Add form contains required title, optional notes, Low/Medium/High priority (Medium by default) and an optional due date: an "Add due date" toggle reveals a date-only picker defaulting to today, and past dates are allowed. New tasks start incomplete. Detail edits these fields with an explicit Save action. Completion is toggled from the list. Delete is available from detail, requires confirmation, and removes the item only after API success.

## Data & API

- No backend. The app talks to a **self-built mock network layer** that returns wire DTOs:
  - `TaskNetworkClient` (`@DependencyClient`, internal to `TaskClient`) is the network boundary. It has async `fetchTasks`, `createTask(TaskDraftDTO)`, `updateTask(TaskDTO)` and `deleteTask(id:)`, and throws `TaskNetworkError` (`.badRequest` / `.notFound` / `.serverError`, mirroring HTTP 400/404/5xx).
  - Its `liveValue` is `MockNetworkClient`, an actor holding in-memory state that simulates latency and failures, assigns IDs, trims titles and rejects blank ones. **This `liveValue` is the single place to swap in a real backend.** `previewValue` is the same mock with no latency or failures. `testValue` is unimplemented; tests opt into `.mock(policy:)` explicitly.
  - `TaskClient` (live and preview) is the repository. It resolves `\.taskNetworkClient` per call, maps DTOs ↔ domain `TaskItem`/`TaskDraft`, and maps `TaskNetworkError` → `TaskClientError`. `CancellationError` propagates unchanged.
  - Feature modules depend on `TaskClient` only. The HTTP `NetworkClient` module is kept as scaffold for a future real backend and is currently unused.
- Wire format (JSON-compatible, matching the challenge example): `TaskDTO` = `{ id, title, notes, priority: "Low"|"Medium"|"High", done, due_date? }`; `TaskDraftDTO` = `{ title, notes, priority, due_date? }`; `due_date` is a UTC `yyyy-MM-dd` calendar day.
- `TaskClientError`: `.validation` (bad request), `.notFound`, `.unavailable` (server error or malformed response). The fix for blank titles returns `.validation`, not `.unavailable`.
- `TaskItem` is a `Sendable`, `Equatable` value with UUID identity, title, optional/empty notes, priority (`low`, `medium`, `high`), completion state and an optional due date (calendar day). Seed IDs are stable for the current app session; new IDs are generated by the mock network.
- Seed the exact four challenge examples from a bundled `seed-tasks.json` resource copied verbatim from the challenge (the mock assigns stable IDs `…0001`–`…0004`; no due dates):
  1. Renew domain registration — notes: “Expires end of month” — High — incomplete.
  2. Reply to design feedback — no notes — Medium — incomplete.
  3. Book dentist — no notes — Low — complete.
  4. Migrate the analytics pipeline to the new warehouse and validate dashboards — notes: “Long one — check layout” — Medium — incomplete.
- Reset to these seeds on each process launch; no disk persistence.
- Reads wait a randomized 300–800 ms; writes wait a randomized 100–300 ms so in-flight states are visible. Reads and all writes (create, update/complete, delete) fail roughly 15% of the time with `.serverError`. Inject the clock/delay and failure policy so tests can deterministically exercise both success and failure without real sleeps.
- Normalize title by trimming whitespace and reject empty values. Do not impose an arbitrary maximum or require unique titles; UUID is identity.
- Mutation UI is pessimistic: update confirmed state only after success. Disable the active control while its request is in flight. On failure retain the last confirmed state and draft, showing inline error and Retry at the affected row or form. A failed completion leaves its previous value; failed delete leaves the task and detail/confirmation available.
- If a detail draft has unsaved changes, Back prompts before discarding. Confirmed discard navigates back without a write.
- Child outputs carry created/updated task values or deleted task ID to `TaskBoardFeature`, which updates its list without changing preserved ordering.

## Persistence

None. `MockNetworkClient`'s in-memory state is the source of truth for the current process; tasks reset to the provided examples after relaunch. No `Storage` module.

## Design

- Use the existing `DesignSystem` semantic asset colors, system typography, spacing/radius tokens and components. Retain light/dark asset appearances; no custom brand palette or font.
- iPhone only, portrait only. Adapt task rows and forms to available iPhone widths; do not add iPad-specific UI.
- Priority is never communicated by color alone: the badge includes its text and an accessible label. Completion controls, retry, Save and Delete have clear VoiceOver labels.
- Support Dynamic Type and maintain a minimum 44-point interactive target.
- Error copy and empty-state copy are localized via `L10n`, never hardcoded in feature Views.
- Relative due-date text is formatted in the VM with the injected `\.date`, `\.calendar` and `\.locale` dependencies (never in Views), so tests are deterministic. Date pickers display in UTC (`DueDay.timeZone`) so the edited value is the canonical due day.

## Localization

English only for this exercise, using the existing String Catalog and typed `L10n` accessors so additional languages can be added later.

## Cross-cutting

- Analytics: none.
- App environments/debug override: none.
- Authentication: none.
- Logging: existing `Logging` module; never log task contents or other user-entered text.

## Kit options

- `ios-project-bootstrap`: existing modular scaffold; minimum deployment is iOS 17.0, matching the current Xcode project setting. Swift 6.2 is the compiler/toolchain requirement, independent of the deployment target. Keep APIs iOS 17-compatible or availability-guard newer APIs.
- Pull-to-refresh: the VM exposes `public func refresh() async`, which triggers a reload and awaits the stored load task, so `.refreshable` keeps its spinner until the load finishes. This is a documented exception to the sync-`trigger` contract (R7; recorded in ADR 0003).
- Remove the unused scaffold `HomeFeature` module and its tests.
- UI state observation uses Combine `ObservableObject` / `@Published` and SwiftUI `@ObservedObject` / `@StateObject` for consistency with the existing modular architecture.
- `ios-feature-module`: `TaskBoardFeature` (top-level route, owns TaskDetail push and AddTask sheet), `TaskDetailFeature` (push child), `AddTaskFeature` (sheet child); all use async effects with `TaskClient`. No StateMaker required.
- `ios-dependency-client`: `TaskClient` (repository, public) + `TaskNetworkClient` (network boundary, internal, live = `MockNetworkClient`) in one client module; typed task/priority models; DTO mapping.
- `ios-network-client`: existing HTTP `NetworkClient` kept, unused, as scaffold for a future real backend.
- `ios-storage`: none.
- `ios-analytics`: none.
- `ios-app-environment`: none.
- `ios-design-system`: existing defaults—asset colors, system typography, spacing/radius tokens, basic components.
- `AppDelegate`: none.

## Quality

- Swift Testing for client and feature behavior: mock network seeds/latency/failure/validation; DTO mapping and error mapping; client CRUD and seeded data; search/sort; swipe-delete undo/commit/failure; due-date formatting; async refresh; list loading/empty/error/retry; add/edit/delete success and failure; completion success/failure; stale async-result protection; unsaved-edit discard; output wiring and host list updates.
- Tests use deterministic injected clock/failure policies and client overrides; no `Task.sleep` and no real network access.
- Build and run the app and package tests on the iPhone 18 Pro Max simulator (available iOS 27.0). `xcodebuild` is authorized for this task. Confirm the deployment target remains iOS 17.0.
- Keep the exercise focused on the MVP within the 60-minute challenge. Do not implement stretches until the core flows/states work.

## Execution

- Existing app/project name remains `livecodding` / `Livecodding`; the app's main screen is titled **Task Board**.
- Initial app bootstrap route transitions to the Task Board list route.
- Use the existing app scheme and `.xctestplan`; keep it synced when test targets are added.
- Autopilot will create local commits per phase/module; never push or rewrite history.

## Open / deferred

- Deferred stretch goals: UI state preservation across scene/process recreation, and custom theming beyond the existing light/dark assets.
- No deep links into pushed screens, cross-feature destination enum, or coordinator-owned navigation stack.
- The wire format above is owned by the mock; a real backend must adopt it or the DTO mapping must change.

## Decision log

- **Q1:** Task Board is the top-level screen; Task detail pushes on its host stack; Add is a sheet.
- **Q2–Q4:** Use an in-memory async TaskClient mock; no persistence; inject delay/failure behavior.
- **Q5–Q7:** Pessimistic mutations with retry; trimmed nonempty title, optional notes, Medium default; confirm delete from detail.
- **Q8:** Discuss stretch goals after the core flow.
- **Q9–Q11:** Existing DesignSystem tokens; deployment minimum changed from the challenge's iOS 16+ allowance to iOS 17.0 to honor the selected project setting; no analytics, environment, auth or storage.
- **Q12:** `xcodebuild` is allowed, superseding the earlier SwiftPM-only recommendation; use iPhone 18 Pro Max simulator.
- **Q13–Q18:** Preserve API order; show completed tasks; edit on detail with explicit Save; keep confirmed data on failures; provide loading/empty/error states; all reads and writes may fail.
- **Q19–Q21:** Confirm discard of dirty edits; disable active controls during writes; trim/reject blank titles, allow duplicates, no arbitrary max.
- **Q22–Q24:** iPhone-only portrait; English String Catalog; Dynamic Type/VoiceOver/44-point accessibility baseline.
- **Q25–Q28:** Delay reads only; successful Add dismisses and appends; successful edit stays on detail; use UUID-based async CRUD operations.
- **Q29–Q30:** Show write errors inline at the affected row/form; priority uses a text badge with subtle color accent and accessible text.
- **R1 (2026-09-30 alignment review, revised):** The mock network layer is `TaskNetworkClient` returning DTOs, with live = `MockNetworkClient` (a single swap point for a real backend), preview = instant mock, and tests opting in. `TaskClient` becomes the repository mapping DTOs/errors. A fake HTTP server was considered and rejected as heavier than needed. `NetworkClient` is kept unused.
- **R2:** Add swipe-to-delete with an undo window (deferred commit, a deliberate exception to pessimistic mutations); detail delete is unchanged.
- **R3:** Writes get 100–300 ms latency; reads stay 300–800 ms.
- **R4:** Async `refresh()` on TaskBoardViewModel for `.refreshable` (R7 exception, ADR 0003).
- **R5:** Stretch goals in scope: search by title, sort by priority/status, due dates with relative formatting.
- **R6:** Remove the unused HomeFeature; keep the iOS 17.0 minimum (satisfies "iOS 16+").
