# Task Board — Spec (confirmed 2026-09-30, revised 2026-09-30 for challenge alignment, body updated 2026-10-06 for R7–R10)

## Goal, users, MVP scope, non-goals

Build a small, polished task board for an individual to track personal tasks during a 60-minute AI-assisted live-coding exercise. The MVP lets the user browse seeded tasks, add a task, view/edit a task, mark it complete, and delete it (from detail, or by swiping in the list with undo). The list demonstrates loading, empty, and error states against a self-built mock network layer (and, since R7, an optional Go backend). Selected stretch goals: search by title, sort by priority/completion, swipe-to-delete with undo, and due dates with relative formatting.

**Non-goals:** authentication, analytics, tabs, UI state restoration, and custom theming beyond the existing light/dark DesignSystem assets. The selected stretch goals are built only after the core flow and all its states work. (Backend/real HTTP integration and environment switching were non-goals until R7; persistence across launches until R8.)

## Screens

| Screen | Module | Placement | Data source | States | Outputs |
|---|---|---|---|---|---|
| Task Board list | `TaskBoardFeature` | Initial top-level route after Bootstrap; owns its host-scoped `NavigationStack` | `TaskClient.fetchTasks()` | Initial loading; empty with Add action; load error with Retry; content; no search results; reload error banner while retaining existing content; cached list shown first, with an offline banner ("Showing saved tasks") and Retry if the fetch fails (R8); per-row "Not synced yet" badge and "N changes waiting to sync" banner (R9); sync-conflict banner with OK (R9); pending-delete undo banner | Add opens sheet; row tap pushes detail; completion toggle is optimistic with rollback (R10); swipe deletes with undo; search and sort are local |
| Add task | `AddTaskFeature` | Sheet from `TaskBoardFeature` | `TaskClient.createTask(_:)` | Editable form including optional due date; saving with active controls disabled; inline error with Retry | Success dismisses and appends the new task; failure keeps the sheet and draft |
| Task detail/edit | `TaskDetailFeature` | Push on `TaskBoardFeature`'s `NavigationStack`; route carries task ID only | Task passed from list; `TaskClient.updateTask(_:)` / `deleteTask(id:)` | Editable draft including optional due date; saving; inline retryable error; delete confirmation | Save remains on detail and reports updated task to host; delete success reports ID and pops; Back with unsaved edits asks to discard |
| Debug Menu | `DebugMenuFeature` | Coordinator overlay sheet (not a route) opened from a floating 🐞 button that `CoordinatorView` layers over every screen; debug and non-prod builds only (R7) | `EnvironmentClient` (`current()`, `selectableEnvironments()`) | Environment list (`local`, `dev`, `prod`) with the active one marked; Close | Picking another environment → coordinator's ordered reset `switchEnvironment(to:)` (back to Bootstrap); Close or swiping the sheet away closes it; picking the active one just closes |

Task rows show title, a Low/Medium/High text badge with a subtle semantic color accent, a completion toggle and, when set, a relative due-date line (e.g. "Due tomorrow", "Overdue by 2 days"; overdue incomplete tasks use the error color plus text, never color alone). Tapping a row (outside the completion control) opens detail. Completed tasks remain visible, checked and visually subdued.

The list is a SwiftUI `List` (needed for `.swipeActions`). Default order is seed/API order: new tasks are appended, and editing or completing doesn't reorder. A toolbar sort menu offers **Default**, **Priority** (High → Low) and **Status** (incomplete first). Ties keep API order. Sorting is local and resets to Default on relaunch.

`.searchable` filters by title: case- and diacritic-insensitive substring, trimmed, applied after sorting. If tasks exist but none match, the list shows a "No matching tasks" state, separate from the empty state. Search and sort never trigger network calls.

**Swipe-to-delete with undo** is optimistic, like completion (R10). A trailing swipe hides the row at once and shows an undo banner for 4 s, timed by an injected clock. Undo restores the row with no request. When the window expires, `deleteTask` is sent. On failure the row is restored in its original position with an inline row error and Retry. Only one delete is pending at a time: a second swipe commits the first immediately. Reloads keep pending rows hidden. Delete from detail keeps the confirmation and stays pessimistic.

The list has a Task Board title and an Add action. The Add form contains required title, optional notes, Low/Medium/High priority (Medium by default) and an optional due date: an "Add due date" toggle reveals a date-only picker defaulting to today, and past dates are allowed. New tasks start incomplete. Detail edits these fields with an explicit Save action. Completion is toggled from the list. Delete is available from detail, requires confirmation, and removes the item only after API success.

## Data & API

- The app talks to a **self-built mock network layer** (`local` environment) or an HTTP backend (`dev`/`prod`; `dev` is the Go server in `backend/`), both behind one DTO boundary (R7):
  - `TaskNetworkClient` (`@DependencyClient`, internal to `TaskClient`) is the network boundary. It has async `fetchTasks`, `createTask(TaskDraftDTO, idempotencyKey:)`, `updateTask(TaskDTO, ifMatch:)` and `deleteTask(id:, ifMatch:)`, and throws `TaskNetworkError` (`.badRequest` / `.notFound` / `.conflict` / `.serverError` / `.transport`, mirroring HTTP 400/404/412/5xx and no usable response).
  - Its `liveValue` resolves the backend on every call from `\.environmentClient.current().apiBackend`: `.mock` → the shared `MockNetworkClient`, an actor holding in-memory state that simulates latency and failures, assigns IDs, trims titles and rejects blank ones; `.remote(url)` → HTTP through `NetworkClient` (`TaskNetworkClient+HTTP.swift`); `.notConfigured` (prod without a URL) → `EnvironmentError.apiBaseURLMissing`. `previewValue` is the mock with no latency or failures. `testValue` is unimplemented; tests opt into `.mock(policy:)` explicitly.
  - `TaskClient` (live and preview) is the repository. It resolves `\.taskNetworkClient`, `\.taskCacheClient` and `\.environmentClient` per call, maps DTOs ↔ domain `TaskItem`/`TaskDraft`, maps `TaskNetworkError` → `TaskClientError`, writes results through to the cache and queues offline changes (see Persistence). `CancellationError` propagates unchanged.
  - Feature modules depend on `TaskClient` only. `NetworkClient` provides the HTTP transport (with a logging middleware) and `NetworkMonitorClient` (network path changes).
- Wire format (JSON-compatible, matching the challenge example; contract in [`backend/openapi.yaml`](../backend/openapi.yaml)): `TaskDTO` = `{ id, title, notes, priority: "Low"|"Medium"|"High", done, due_date?, version? }`; `TaskDraftDTO` = `{ title, notes, priority, due_date? }`; `due_date` is a UTC `yyyy-MM-dd` calendar day; `version` is the server's revision (1 on create, +1 per update).
- `TaskClientError`: `.validation` (bad request), `.notFound`, `.unavailable` (server error, no connection, malformed response or no base URL configured). The fix for blank titles returns `.validation`, not `.unavailable`.
- `TaskItem` is a `Sendable`, `Equatable` value with UUID identity, title, optional/empty notes, priority (`low`, `medium`, `high`), completion state, an optional due date (calendar day) and `isPendingSync` (a queued offline change). Seed IDs are stable; new IDs are generated by the server or mock (offline creates get a temporary local id until synced, R9).
- Seed the local mock with the exact four challenge examples from a bundled `seed-tasks.json` resource copied verbatim from the challenge (the mock assigns stable IDs `…0001`–`…0004`; no due dates):
  1. Renew domain registration — notes: “Expires end of month” — High — incomplete.
  2. Reply to design feedback — no notes — Medium — incomplete.
  3. Book dentist — no notes — Low — complete.
  4. Migrate the analytics pipeline to the new warehouse and validate dashboards — notes: “Long one — check layout” — Medium — incomplete.
- The local mock resets to these seeds on each process launch (the Go backend embeds the same seeds); the on-disk cache still shows the last known list first (see Persistence).
- In the local mock, reads wait a randomized 300–800 ms; writes wait a randomized 100–300 ms so in-flight states are visible. Reads and all writes (create, update/complete, delete) fail roughly 15% of the time with `.serverError`. The Go backend reproduces this with `make run-chaos`. Inject the clock/delay and failure policy so tests can deterministically exercise both success and failure without real sleeps.
- Normalize title by trimming whitespace and reject empty values. Do not impose an arbitrary maximum or require unique titles; UUID is identity.
- Mutation rules:
  - **Completion** is optimistic (R10): the toggle shows at once; on failure the row rolls back to the last confirmed value with an inline error and Retry. Toggles during a request coalesce into one follow-up request with the latest value.
  - **Swipe-delete** is optimistic with a 4 s undo window (above).
  - **Create, edit and detail delete** wait for the client: the active control is disabled while the request is in flight; on failure the draft (or the task, for delete) stays, with an inline error and Retry at the form.
  - **Offline queue** (R9): when the server can't be reached (`.unavailable`), any create/update/delete is queued and returned as a success, marked `isPendingSync`; validation and not-found errors still fail.
- If a detail draft has unsaved changes, Back prompts before discarding. Confirmed discard navigates back without a write.
- Child outputs carry created/updated task values or deleted task ID to `TaskBoardFeature`, which updates its list without changing preserved ordering.

## Persistence

GRDB (SQLite) inside `TaskClient` (`TaskCacheClient`, `Library/Caches/TaskCache.sqlite`), not a `Storage` module (R8, R9; details in the [TaskClient README](../Modules/Sources/TaskClient/README.md)):

- **Cache:** every successful fetch/create/update/delete is written through; cache write errors are logged, never surfaced. On a load with nothing on screen the board shows the cached list first, then the fetched one (stale-while-revalidate). Rows are tagged with their environment.
- **Pending-change queue:** offline changes, one per task (later changes merge), sent oldest first before each fetch, on network-path recovery and on a backoff retry (5 s doubling to 5 min). Creates carry an `Idempotency-Key`; queued updates/deletes carry the version they were made on (`If-Match`; `412` → dropped, server wins, conflict banner).
- Both are cleared on every environment switch (unsynced changes are lost). The server (or the local mock) stays the source of truth.
- The environment override is stored in `UserDefaults` by `AppEnvironment`.

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
- App environments/debug override: `local` / `dev` / `prod` in `AppEnvironment`; runtime override from the Debug Menu in debug and non-prod builds (R7).
- Authentication: none.
- Logging: existing `Logging` module; never log task contents or other user-entered text.

## Kit options

- `ios-project-bootstrap`: existing modular scaffold; minimum deployment is iOS 17.0, matching the current Xcode project setting. Swift 6.2 is the compiler/toolchain requirement, independent of the deployment target. Keep APIs iOS 17-compatible or availability-guard newer APIs.
- Pull-to-refresh: the VM exposes `public func refresh() async`, which triggers a reload and awaits the stored load task, so `.refreshable` keeps its spinner until the load finishes. This is a documented exception to the sync-`trigger` contract (R7; recorded in ADR 0003).
- Remove the unused scaffold `HomeFeature` module and its tests.
- UI state observation uses Combine `ObservableObject` / `@Published` and SwiftUI `@ObservedObject` / `@StateObject` for consistency with the existing modular architecture.
- `ios-feature-module`: `TaskBoardFeature` (top-level route, owns TaskDetail push and AddTask sheet), `TaskDetailFeature` (push child), `AddTaskFeature` (sheet child); all use async effects with `TaskClient`. `DebugMenuFeature` (coordinator overlay sheet, R7). No StateMaker required.
- `ios-dependency-client`: `TaskClient` (repository, public) + `TaskNetworkClient` (network boundary, internal, live = per-call backend from `AppEnvironment`: `MockNetworkClient` or HTTP) + `TaskCacheClient` (GRDB, internal) in one client module; typed task/priority models; DTO mapping.
- `ios-network-client`: HTTP `NetworkClient` (`Endpoint`, JSON decoding, logging middleware) used by `TaskClient`'s HTTP backend, plus `NetworkMonitorClient`. No auth, retry or correlation-id middlewares (sync retry backoff lives in `TaskBoardFeature`).
- `ios-storage`: not used; persistence is GRDB inside `TaskClient` (R8).
- `ios-analytics`: none.
- `ios-app-environment`: `AppEnvironment` (`local`/`dev`/`prod` from CI-generated `BuildValues+Generated.swift`, no xcconfig) + `DebugMenuFeature` for the runtime override (R7).
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
- The wire contract is owned by [`backend/openapi.yaml`](../backend/openapi.yaml): `version` on every task, `If-Match: "<version>"` on `PUT`/`DELETE` (`412` on mismatch) and `Idempotency-Key` on `POST /tasks`. `MockNetworkClient` and the DTO mapping follow it.

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
- **R7 (post-challenge, 2026-10-06):** Environment switching is now in scope, superseding the non-goal. `AppEnvironment` has `local` (in-app mock), `dev` (`http://localhost:8080`, the Go server in `backend/`) and `prod` (no URL yet; calls fail with `apiBaseURLMissing`). Values come from a committed `BuildValues+Generated.swift` that CI regenerates (`scripts/generate-build-values.sh`); no xcconfig. `TaskNetworkClient.liveValue` picks mock or HTTP per call. A Debug Menu opened from a floating button switches environments in debug/non-prod builds (ordered reset in the coordinator). `NSAllowsLocalNetworking` is added for Debug only via `Config/Debug-Info.plist`.
- **R8 (post-challenge, 2026-10-06):** Offline cache is now in scope, superseding "persistence across launches" as a non-goal. `TaskClient` writes every successful fetch/create/update/delete through to an internal GRDB `TaskCacheClient` (SQLite in Caches); cache write errors are logged, never surfaced. New `TaskClient.cachedTasks` and `TaskClient.clearCache`; `AppCoordinator.switchEnvironment` clears the cache as step 3 of the ordered reset. Rows stay tagged with their environment and are read by the current one, so a response landing after the switch never appears in the new environment. On a load with nothing on screen, `TaskBoardFeature` shows cached tasks first (stale-while-revalidate); if the fetch then fails, the cached list stays with the reload banner reading "Can't reach the server. Showing saved tasks." and Retry. The server stays the source of truth: no offline writes or sync queue (*amended by R9*).
- **R9 (post-challenge, 2026-10-06):** Offline changes. When a create/update/delete fails with `.unavailable`, `TaskClient` queues it in a GRDB `pendingChange` table (one row per task; later changes merge into it; a create then delete is dropped without a request) and returns success with `TaskItem.isPendingSync`. Validation and not-found errors are still thrown. Changes to a task that already has a queued change go straight to the queue. `fetchTasks` sends the queue first (oldest first, one sync at a time); a change the server can't take now stays queued and the fetch still runs (it fails on its own if the server is down), so one failing change never blocks the list. Each request and its result are recorded together even if the load is cancelled, so a create is never sent twice. Triggers: every load (appear, Retry, pull-to-refresh), the device getting a network path back (`NetworkMonitorClient`, NWPathMonitor), and a backoff retry in `TaskBoardFeature` while changes are waiting (5 s doubling to 5 min, reset when the queue empties or the path comes back). Offline creates get a temporary id; the server's id replaces it in the database (`taskAlias`), and later calls with the temporary id are mapped. Completion of an offline create is sent as a follow-up update. Creates are idempotent: `POST /tasks` carries an `Idempotency-Key` (the task's local id, also used when the create is queued), and the server returns the task it already created for a repeated key, so a lost answer or a retried sync never duplicates a task. Conflicts (queued changes only): server wins. Tasks carry a server `version` (1 on create, +1 per update); the client records the last version it saw per task (`taskVersion`), a queued update/delete keeps the version it was made on (`pendingChange.baseVersion`; merges keep the first) and is sent with `If-Match`. On `412` an update whose values the server already has (a lost answer) counts as applied; otherwise the change is dropped (edits made while it was in flight too), logged (`taskSync.conflict`) and counted (`syncConflict`); the board shows "N offline changes weren't applied: … changed on the server" with OK to dismiss. Online edits and changes without a known version (offline creates, an older server) are last write wins. A change the server refuses (400/404) is dropped and logged (`taskSync.rejected`), and the fetch that follows shows the server's version. UI: a per-row "not synced" badge and a banner "N changes waiting to sync" (GRDB observation). Switching environments discards unsynced changes along with the cache.
- **R10 (post-challenge, 2026-10-06):** Optimistic completion. A toggle shows at once; on failure the row rolls back to the last confirmed value with an inline error and Retry. Toggles during a request are coalesced into one follow-up request with the latest value.
