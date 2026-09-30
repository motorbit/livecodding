# TaskBoardFeature

Top-level Task Board screen (route `.taskBoard` in `AppCoordinator`). Owner: Task Board feature.

## Wiring

- Coordinator: `withDependencies(from: self) { TaskBoardViewModel() }` → `TaskBoardView(viewModel:)`.
  The host has **no output events**; all navigation below the list is host-scoped.
- Data: `@Dependency(\.taskClient)` — `fetchTasks()` on first appear / Retry / pull-to-refresh,
  `updateTask(_:)` for pessimistic completion toggles, `deleteTask(id:)` for swipe-to-delete.
  `\.continuousClock` drives the undo window (tests inject `TestClock`).

## Host-scoped navigation

- Owns `NavigationStack(path:)` with `[TaskBoardRoute]`; `.detail(id: UUID)` carries only the ID.
- Owns `detailViewModel: TaskDetailViewModel?` (push) and `addViewModel: AddTaskViewModel?` (sheet),
  both created with `withDependencies(from: self)` and wired through `onEvent`. The host never
  calls a child's `trigger`.
- `AddTask`: `.created` appends (API order preserved) and dismisses; `.closeRequested` dismisses.
- `TaskDetail`: `.dirtyChanged` gates Back; `.updated` replaces by ID and stays; `.deleted` removes and pops.
- Dirty Back: the system back button is hidden while dirty and replaced by a host Back button; a
  path change to `[]` while dirty (e.g. swipe) is rejected and shows the discard confirmation.
  Discard pops and drops the child VM; Cancel keeps detail.

## States

Initial loading → content / empty (with Add) / failed (with Retry). A reload failure with existing
content keeps the list and shows an inline banner with Retry. Completion is pessimistic per row:
the toggle is disabled while in flight, the prior value stays on failure with an inline Retry.
If a successful mutation races a fetch, the stale fetch result is discarded and the board fetches
again so it cannot revert the confirmed mutation.

## Swipe to delete with undo

The list is a plain `List`; a trailing swipe sends `.deleteSwiped(id)`. This is the one deliberate
exception to pessimistic updates (SPEC R2):

- The row hides immediately and an undo banner appears for `undoWindow` (4 s).
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

- Strings come from `L10n.TaskBoard` (discard confirmation reuses `L10n.TaskDetail`).
- Task contents are never logged.
