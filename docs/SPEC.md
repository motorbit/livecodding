# Task Board — Spec (confirmed 2026-09-30)

## Goal, users, MVP scope, non-goals

Build a small, polished task board for an individual to track personal tasks during a 60-minute AI-assisted live-coding exercise. The MVP lets the user browse seeded tasks, add a task, view/edit a task, mark it complete, and delete it. The list demonstrates loading, empty, and error states against an asynchronous mock API.

**Non-goals:** backend or real HTTP integration, authentication, analytics, environment switching, persistence across launches, due dates, tabs, and stretch features before the core flow is complete. Discuss stretch goals only after the MVP is working.

## Screens

| Screen | Module | Placement | Data source | States | Outputs |
|---|---|---|---|---|---|
| Task Board list | `TaskBoardFeature` | Initial top-level route after Bootstrap; owns its host-scoped `NavigationStack` | `TaskClient.fetchTasks()` | Initial loading; empty with Add action; load error with Retry; content; reload error banner while retaining existing content | Add opens sheet; row tap pushes detail; completion toggle updates through client |
| Add task | `AddTaskFeature` | Sheet from `TaskBoardFeature` | `TaskClient.createTask(_:)` | Editable form; saving with active controls disabled; inline error with Retry | Success dismisses and appends the new task; failure keeps the sheet and draft |
| Task detail/edit | `TaskDetailFeature` | Push on `TaskBoardFeature`'s `NavigationStack`; route carries task ID only | Task passed from list; `TaskClient.updateTask(_:)` / `deleteTask(id:)` | Editable draft; saving; inline retryable error; delete confirmation | Save remains on detail and reports updated task to host; delete success reports ID and pops; Back with unsaved edits asks to discard |

Task rows show title, a Low/Medium/High text badge with a subtle semantic color accent, and a completion toggle. Tapping a row (outside the completion control) opens detail. Completed tasks remain visible, checked and visually subdued. Preserve seed/API order; append newly created tasks and do not reorder when editing or completing.

The list has a Task Board title and an Add action. The Add form contains required title, optional notes, and Low/Medium/High priority (Medium by default); new tasks start incomplete. Detail edits these fields with an explicit Save action. Completion is toggled from the list. Delete is available from detail, requires confirmation, and removes the item only after API success.

## Data & API

- No backend. Add a `TaskClient` client module with async `fetchTasks`, `createTask`, `updateTask`, and `deleteTask` operations. Its live implementation uses an in-memory actor-backed mock source; feature modules depend on `TaskClient`, not `NetworkClient`.
- `Task` is a `Sendable`, `Equatable` value with UUID identity, title, optional/empty notes, priority (`low`, `medium`, `high`) and completion state. Seed IDs are stable for the current app session; new IDs are generated.
- Seed the exact four challenge examples:
  1. Renew domain registration — notes: “Expires end of month” — High — incomplete.
  2. Reply to design feedback — no notes — Medium — incomplete.
  3. Book dentist — no notes — Low — complete.
  4. Migrate the analytics pipeline to the new warehouse and validate dashboards — notes: “Long one — check layout” — Medium — incomplete.
- Reset to these seeds on each process launch; no disk persistence.
- Reads wait a randomized 300–800 ms. Writes are async without artificial latency. Reads and all writes (create, update/complete, delete) fail roughly 15% of the time. Inject the clock/delay and failure policy so tests can deterministically exercise both success and failure without real sleeps.
- Normalize title by trimming whitespace and reject empty values. Do not impose an arbitrary maximum or require unique titles; UUID is identity.
- Mutation UI is pessimistic: update confirmed state only after success. Disable the active control while its request is in flight. On failure retain the last confirmed state and draft, showing inline error and Retry at the affected row or form. A failed completion leaves its previous value; failed delete leaves the task and detail/confirmation available.
- If a detail draft has unsaved changes, Back prompts before discarding. Confirmed discard navigates back without a write.
- Child outputs carry created/updated task values or deleted task ID to `TaskBoardFeature`, which updates its list without changing preserved ordering.

## Persistence

None. The in-memory mock is the source of truth for the current process; tasks reset to the provided examples after relaunch. No `Storage` module.

## Design

- Use the existing `DesignSystem` semantic asset colors, system typography, spacing/radius tokens and components. Retain light/dark asset appearances; no custom brand palette or font.
- iPhone only, portrait only. Adapt task rows and forms to available iPhone widths; do not add iPad-specific UI.
- Priority is never communicated by color alone: the badge includes its text and an accessible label. Completion controls, retry, Save and Delete have clear VoiceOver labels.
- Support Dynamic Type and maintain a minimum 44-point interactive target.
- Error copy and empty-state copy are localized via `L10n`, never hardcoded in feature Views.

## Localization

English only for this exercise, using the existing String Catalog and typed `L10n` accessors so additional languages can be added later.

## Cross-cutting

- Analytics: none.
- App environments/debug override: none.
- Authentication: none.
- Logging: existing `Logging` module; never log task contents or other user-entered text.

## Kit options

- `ios-project-bootstrap`: existing modular scaffold; minimum deployment is now iOS 16.0. Swift 6.2 is the compiler/toolchain requirement, independent of the deployment target. Keep APIs iOS 16-compatible or availability-guard newer APIs.
- `ios-feature-module`: `TaskBoardFeature` (top-level route, owns TaskDetail push and AddTask sheet), `TaskDetailFeature` (push child), `AddTaskFeature` (sheet child); all use async effects with `TaskClient`. No StateMaker required.
- `ios-dependency-client`: new `TaskClient`, in-memory mock source, typed task/priority models; it does not depend on `NetworkClient`.
- `ios-network-client`: existing `NetworkClient` includes JSON and Endpoint support, but is intentionally not used for this mock-only exercise.
- `ios-storage`: none.
- `ios-analytics`: none.
- `ios-app-environment`: none.
- `ios-design-system`: existing defaults—asset colors, system typography, spacing/radius tokens, basic components.
- `AppDelegate`: none.

## Quality

- Swift Testing for client and feature behavior: client CRUD and seeded data; list loading/empty/error/retry; add/edit/delete success and failure; completion success/failure; stale async-result protection; unsaved-edit discard; output wiring and host list updates.
- Tests use deterministic injected clock/failure policies and client overrides; no `Task.sleep` and no real network access.
- Build and run the app and package tests on the iPhone 18 Pro Max simulator (available iOS 27.0). `xcodebuild` is authorized for this task. Confirm the deployment target remains iOS 16.0.
- Keep the exercise focused on the MVP within the 60-minute challenge. Do not implement stretches until the core flows/states work.

## Execution

- Existing app/project name remains `livecodding` / `Livecodding`; the app's main screen is titled **Task Board**.
- Initial app bootstrap route transitions to the Task Board list route.
- Use the existing app scheme and `.xctestplan`; keep it synced when test targets are added.
- No commits unless requested.

## Open / deferred

- All stretch goals are deferred until the MVP is complete; then review search/filter, sorting, swipe-to-delete with undo, persistence, due dates, and additional theming as time permits.
- No deep links into pushed screens, cross-feature destination enum, or coordinator-owned navigation stack.
- No API contract exists because the data source is an in-memory mock.

## Decision log

- **Q1:** Task Board is the top-level screen; Task detail pushes on its host stack; Add is a sheet.
- **Q2–Q4:** Use an in-memory async TaskClient mock; no persistence; inject delay/failure behavior.
- **Q5–Q7:** Pessimistic mutations with retry; trimmed nonempty title, optional notes, Medium default; confirm delete from detail.
- **Q8:** Discuss stretch goals after the core flow.
- **Q9–Q11:** Existing DesignSystem tokens; iOS 16 minimum (superseding the repository's former iOS 26 floor); no analytics, environment, auth or storage.
- **Q12:** `xcodebuild` is allowed, superseding the earlier SwiftPM-only recommendation; use iPhone 18 Pro Max simulator.
- **Q13–Q18:** Preserve API order; show completed tasks; edit on detail with explicit Save; keep confirmed data on failures; provide loading/empty/error states; all reads and writes may fail.
- **Q19–Q21:** Confirm discard of dirty edits; disable active controls during writes; trim/reject blank titles, allow duplicates, no arbitrary max.
- **Q22–Q24:** iPhone-only portrait; English String Catalog; Dynamic Type/VoiceOver/44-point accessibility baseline.
- **Q25–Q28:** Delay reads only; successful Add dismisses and appends; successful edit stays on detail; use UUID-based async CRUD operations.
- **Q29–Q30:** Show write errors inline at the affected row/form; priority uses a text badge with subtle color accent and accessible text.
