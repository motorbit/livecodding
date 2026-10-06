# TaskBoardFeature

Top-level Task Board screen (route `.taskBoard` in `AppCoordinator`). Owner: Task Board feature.

## Wiring

- Coordinator: `withDependencies(from: self) { TaskBoardViewModel() }` → `TaskBoardView(viewModel:)`.
  The host has **no output events**; all navigation below the list is host-scoped.
- Data: `@Dependency(\.taskClient)` — `fetchTasks()` on first appear / Retry / pull-to-refresh,
  `updateTask(_:)` for optimistic completion toggles, `deleteTask(id:)` for swipe-to-delete.
  `\.continuousClock` drives the undo window (tests inject `TestClock`); `\.date`, `\.calendar`,
  `\.locale` drive due-date text.

## Host-scoped navigation

- Owns `NavigationStack(path:)` with `[TaskBoardRoute]`; `.detail(id: UUID)` carries only the ID.
- Owns `detailViewModel: TaskDetailViewModel?` (push) and `addViewModel: AddTaskViewModel?` (sheet),
  both created with `withDependencies(from: self)` and wired through `onEvent`. The host never
  calls a child's `trigger`.
- `AddTask`: `.created` appends (API order preserved) and dismisses; `.closeRequested` dismisses.
  If the board had no loaded list yet (`.loading`/`.failed`), `.created` also starts a reload so the
  rest of the tasks appear; a failure there shows the reload banner with Retry.
- `TaskDetail`: `.dirtyChanged` gates Back; `.updated` replaces by ID and stays; `.deleted` removes and pops.
- Dirty Back: the system back button is hidden while dirty and replaced by a host Back button; a
  path change to `[]` while dirty (e.g. swipe) is rejected and shows the discard confirmation.
  Discard pops and drops the child VM; Cancel keeps detail.

## States

Initial loading → content / empty (with Add) / failed (with Retry). When nothing is on screen yet,
a load first shows `taskClient.cachedTasks()` (if any; a cache read error is ignored), then the
fetched list. A reload failure with existing content keeps the list and shows an inline banner with
Retry; while the list is still the cached one, the banner says the server can't be reached and the
saved tasks are shown (`L10n.TaskBoard.offlineError`). Completion is optimistic per row: the
toggle applies at once, and a failure rolls back to the confirmed value with an inline Retry.
If a successful mutation races a fetch, the stale fetch result is discarded and the board fetches
again so it cannot revert the confirmed mutation.

## Offline changes

`TaskClient` queues a change it can't send and reports success, so offline mutations look like
successes here. Rows whose task has `isPendingSync` get a badge (`pendingSyncLabel`, "Not synced
yet"). From the first appearance, the VM observes `taskClient.pendingSyncCounts()`
(`pendingSyncTask`) and shows `pendingSyncMessage` ("N changes waiting to sync") while the count is
above zero. It also observes `taskClient.syncConflictCounts()` (`syncConflictTask`) and shows
`syncConflictMessage` ("N offline changes weren't applied: … changed on the server") with an OK
button; `.syncConflictDismissed` hides it at once and calls `dismissSyncConflicts()`
(`dismissConflictsTask`). It also observes `networkMonitorClient.isOnlineUpdates()` (`connectivityTask`) and
reloads when the path goes from offline to online. Every load syncs first (inside `fetchTasks`).
While changes are waiting and the device isn't known to be offline, the VM retries with backoff
(`syncRetryTask`, injected `continuousClock`): it reloads after 5 s, then 10, 20 … up to 5 min
(`syncRetryDelay(attempt:)`). The count dropping to zero cancels the retry and resets the backoff;
going offline cancels it, and getting the path back reloads and resets it. A retry never cancels a
load that is already running (that load reschedules when it finishes), and it reloads quietly: the
phase and the reload banner stay until the result arrives.

A detail opened on a task created offline keeps its temporary id. If a reload replaces it with the
server's id meanwhile, detail's `.updated`/`.deleted` no longer match a row; `TaskClient` has
already applied the change under the server's id, so the board reloads instead. That reload reads
the cache first, so the change shows even when the fetch fails offline.

## Search and sort

Local only; never triggers a request. `rebuildRows()` stable-sorts `tasks` by `state.sortOrder`
(`TaskSortOrder`: Default = API order, Priority = High → Low, Status = incomplete first; ties keep
API order), then filters by the trimmed `searchText` with `localizedStandardContains` (case- and
diacritic-insensitive). `isNoResults` (tasks exist, none match) shows "No matching tasks" inside the
`.content` phase; `.empty` still means no tasks at all. Both reset on relaunch.

## Due dates

Rows show `dueText`/`isOverdue`, built in `rebuildRows()` from `\.date.now` + `\.calendar` (local
today → `DueDay`) and `\.locale` (plural rules): "Due today", "Due tomorrow", "Due in N days";
past days show "Overdue by N days" (error color) for incomplete tasks and "Due yesterday" /
"Due N days ago" for completed ones. `\.date` is read only when a visible task has a due date.
`.dayMayHaveChanged` (scene becomes active, or `significantTimeChangeNotification`) recomputes it.

## Swipe to delete with undo

The list is a plain `List`; a trailing swipe sends `.deleteSwiped(id)`. Completion toggles and swipe-delete are
optimistic (SPEC R2):

- **Completion:** the row shows the new value at once, with no spinner. If the request fails, the
  row goes back to the server's last confirmed value with `completionError` and Retry. Toggles made
  while a request is in flight only change the row. When that request answers, the latest value is
  sent if it differs, so requests for one row never race. A reload keeps the value of a row whose
  request is in flight. Detail can't be opened until the request answers (see Gotchas).

Swipe-delete:

- The row hides immediately and an undo banner appears for `undoWindow` (4 s).
  VoiceOver announces the banner message when it appears.
- `.undoTapped` restores the row at its original index; no request is sent.
- When the window expires, `deleteTask(id:)` is sent while the row stays hidden. Swiping another row
  commits the pending one immediately (a single undo slot).
- On failure the row is restored in place with `deleteError` and Retry; `.rowRetryTapped` retries
  pessimistically (row visible, spinner). Row Retry also covers failed completion toggles.
- Swipes are ignored while that row has a request in flight. Reloads keep hidden rows hidden.
- A pending, uncommitted delete is dropped if the VM deinits (the task is not deleted).
- Delete from Task Detail is unchanged (confirmation, pessimistic).

## Pull-to-refresh

`.refreshable { await viewModel.refresh() }`. `refresh()` triggers `.refreshRequested`, then awaits
the stored `loadTask`, following any restarted load, so the spinner stays until the result is in
state. It's the only async VM entry point (ADR 0003 exception).

## Gotchas

- A row with any request in flight (completion or delete) can't open detail: both requests send the
  whole task, so a detail save could race them and overwrite or revert each other's fields. A
  successful row delete pops detail if it shows that task.

- Strings come from `L10n.TaskBoard` (discard confirmation reuses `L10n.TaskDetail`).
- Task contents are never logged.
