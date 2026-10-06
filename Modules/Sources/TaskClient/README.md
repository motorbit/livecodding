# TaskClient

Data layer for the Task Board. Features use only the public `TaskClient` (domain `TaskItem` / `TaskDraft`).

```
Feature VM ──▶ TaskClient (repository) ──▶ TaskNetworkClient (DTOs) ──┬─▶ MockNetworkClient (actor, `local`)
               DTO ↔ domain, error mapping     network boundary          └─▶ HTTP via NetworkClient (`dev`/`prod`)
               write-through, offline queue ▶ TaskCacheClient (GRDB/SQLite, scope = environment)
```

## TaskClient (public)

| Endpoint | Signature |
|---|---|
| `fetchTasks` | `() async throws -> [TaskItem]`: sends queued changes, then fetches and replaces the cache; queued changes are applied on top |
| `cachedTasks` | `() async throws -> [TaskItem]`: the last known list for the active environment with queued changes applied; empty if none |
| `clearCache` | `() async throws -> Void`: empties the cache and the queue (environment switch); logs errors (`taskCache.clear`) and rethrows |
| `createTask` | `(TaskDraft) async throws -> TaskItem` |
| `updateTask` | `(TaskItem) async throws -> TaskItem` |
| `deleteTask` | `(UUID) async throws -> Void` |
| `pendingSyncCounts` | `() -> AsyncStream<Int>`: queued changes in the active environment, current value then every change |
| `syncConflictCounts` | `() -> AsyncStream<Int>`: queued changes dropped because the task changed on the server, not yet dismissed; current value then every change |
| `dismissSyncConflicts` | `() async throws -> Void`: forgets those conflicts; logs errors (`taskCache.write`) and rethrows |

Errors: `TaskClientError.validation` (blank title), `.notFound`, `.unavailable` (server failure, no connection, malformed response or no base URL configured). `CancellationError` passes through.

- `liveValue` / `previewValue`: `TaskClient.repository`, which resolves `\.taskNetworkClient`, `\.taskCacheClient` and `\.environmentClient` per call. After each successful network call it updates the cache (`replaceAll` / `upsert` / `delete`). The cache scope is read before the network call, so an environment switch mid-request can't write into the new environment's cache. A cache write error is logged (`operation: taskCache.write`) and never fails the call; `cachedTasks` logs read errors (`taskCache.read`) and rethrows. A failed network call leaves the cache untouched.
- `testValue`: unimplemented. Feature tests override its endpoints.

## Offline changes and sync (`TaskClient+Sync.swift`)

- **Queueing.** A create/update/delete whose network call fails with `.unavailable` is queued and returns success. Returned items have `isPendingSync`, and offline creates get a temporary id from `\.uuid`. Titles are validated locally first (trimmed, not blank → `.validation`). A task that already has a queued change skips the network and queues behind it. If the queue can't be written, the caller gets `.unavailable`.
- **Merging.** One change per task: create/update + update → same kind with the newer values; create/update + delete → delete (a never-synced create is then dropped without a request); anything after a delete is ignored. Every merge bumps `revision`.
- **Sync.** `fetchTasks` sends the queue first, oldest first, under `TaskCacheClient.serialized` (one sync per database). The first `.unavailable` stops it; the change stays queued and `fetchTasks` still fetches, so a change the server keeps failing (5xx) never blocks the list. Each send and its `settle` run in a task the caller can't cancel, so a cancelled load never loses a server id and re-sends a create.
  - **Conflicts: server wins.** Every response with a `version` (fetch, create, update) is recorded in `taskVersion`; the sync's own results carry it in `SyncOutcome` and `settle` records it in the same transaction. A queued update/delete stores the version it was made on (`baseVersion`; merges keep the first, a create converted to an update takes the created version) and is sent with `If-Match`. `412` → `TaskNetworkError.conflict` → the change is dropped, even if edited while in flight, logged (`taskSync.conflict`) and counted in `syncConflict` until `dismissSyncConflicts`. The fetch that follows shows the server's version. Before counting a 412 on an update, the sync re-reads the list: if the server already has exactly the queued values (an online save whose answer was lost, then queued), the change counts as applied. Known gap: if such a lost save is edited further offline, the edits are reported as a conflict. Online calls and changes without a known version send no `If-Match` (last write wins).
  - 400 / 404 → dropped and logged (`taskSync.rejected`, kind and reason only); a delete that gets 404 counts as done.
  - A change edited while being sent stays queued (`revision` moved) and goes out in the next pass, up to 3 passes.
- **Server ids.** `POST` returns the server's id; `settle` records `taskAlias(localID → serverID)` and saves the task under the server id. Later calls with the temporary id (a screen that hasn't reloaded yet) are mapped, and the result keeps the caller's id until the next fetch. `POST` can't carry completion, so a task completed offline gets a follow-up `PUT`.
- **Idempotent create.** Every `POST /tasks` carries `Idempotency-Key`. `createTask` draws one id from `\.uuid` and uses it as the key and, if the request fails, as the queued task's local id; the sync sends the queued create with the same key. A create that reached the server but whose answer was lost is therefore returned again (`200`) instead of duplicated. A replay returns the task as first stored, so if the queued values differ (completion, or edits made since), they follow as a `PUT`. Known gap: if such a task is then deleted offline, the delete is treated as never-sent and dropped, so the task comes back on the next fetch. The server keeps keys forever; a key whose task was deleted gets `404`, which drops the queued create. `MockNetworkClient` behaves the same.
- **Display.** `PendingChanges.apply` puts the queue on top of the saved list: updates replace in place, creates append, deletes remove.
- Switching environments clears the queue together with the cache: unsynced changes are lost.

## TaskNetworkClient (internal)

DTO-level CRUD (`TaskDTO`, `TaskDraftDTO`) throwing `TaskNetworkError` (`.badRequest`, `.notFound`, `.conflict`, `.serverError`, `.transport`). `updateTask`/`deleteTask` take an optional `ifMatch` version, sent as `If-Match: "<n>"`; `TaskDTO.version` is optional, so a server without versions still decodes.

- `liveValue`: `.environmentBacked(mock: .mock(policy: .live))`. On **every call** it reads `\.environmentClient.current().apiBackend`:
  - `.mock` → the shared `MockNetworkClient` (one instance per process, so its state survives switches);
  - `.remote(url)` → `.http(baseURL:)` (`TaskNetworkClient+HTTP.swift`): `GET/POST tasks`, `PUT/DELETE tasks/{id}` through `\.networkClient`, off the main actor. 400 → `.badRequest`, 404 → `.notFound`, 412 → `.conflict`, other statuses → `.serverError`, no response or undecodable body → `.transport`, cancellation → `CancellationError`;
  - `.notConfigured` → logs and throws `EnvironmentError.apiBaseURLMissing`.
- `previewValue`: `.mock(policy: .instant)` (no latency, no failures).
- `testValue`: unimplemented. Tests opt in with `$0.taskNetworkClient = .mock(policy: …)` or per-endpoint overrides.

## TaskCacheClient (internal)

On-disk cache of the last known server list, so the board can show tasks before (or without) the network, plus the offline change queue (see above).

- SQLite through GRDB, `Library/Caches/TaskCache.sqlite` (not backed up; the system may purge it, which only costs the first paint). One `task` table keyed by `(scope, id)`, with `position` keeping list order. Ids and priorities are stored as text; a row this version can't read is skipped.
- The whole cache is cleared on every environment switch (`TaskClient.clearCache`, called by `AppCoordinator`). Rows still carry a `scope` (the environment name, read before the network call) and reads filter by the current one, so a response that lands after the switch can't show up in the new environment.
- `TaskCacheDatabase` opens the file and runs `DatabaseMigrator` lazily on first use, off the caller's actor (`@concurrent`). Reads and writes use GRDB's async API.
- Endpoints: `tasks(scope)`, `replaceAll(scope, tasks)`, `upsert(scope, task)` (new tasks append, existing ones keep their position; ignored until `replaceAll` has stored a full list for the scope, tracked in the `cachedScope` table, so a partial list is never shown as the saved one), `delete(scope, id)`, `clear()` (all scopes).
- `liveValue`: the file database. `previewValue` / `.inMemory()`: a private in-memory database. `testValue`: unimplemented.
- Queue endpoints: `pendingChanges(scope)`, `resolve(scope, id)`, `enqueue(scope, LocalChange)`, `settle(scope, change, SyncOutcome)`, `pendingChangeCounts(scope)` (GRDB `ValueObservation`) and `serialized(body)` (an `AsyncLock` per database). Migration `v2-create-pendingChange` adds `pendingChange` (`sequence` autoincrement, unique `(scope, taskID)`) and `taskAlias`.
- Version endpoints: `setVersions(scope, [id: version])`, `syncConflictCounts(scope)` (`ValueObservation`) and `clearSyncConflicts(scope)`. Migration `v3-task-versions` adds `taskVersion` (`(scope, id)` → `version`), `pendingChange.baseVersion` and `syncConflict`. `clear` empties them too.
- Schema changes: add a new migration to `TaskCacheDatabase.migrator`; never edit a shipped one.

## MockNetworkClient

An actor seeded from `Resources/seed-tasks.json` (the challenge examples, stable IDs `…0001`–`…0004`). It resets on every launch. `MockNetworkPolicy.live` delays reads by 300–800 ms and writes by 100–300 ms, and fails about 15 % of calls with `.serverError`. It assigns IDs, trims titles and rejects blank ones (`.badRequest`); unknown IDs give `.notFound`.

## Wire format

`TaskDTO` = `{ id, title, notes, priority: "Low"|"Medium"|"High", done, due_date?, version? }` (`version` is the server's revision; `nil` from a server without versions). `TaskDraftDTO` (the `POST` body) = `{ title, notes, priority, due_date? }`, with no `id`, `done` or `version`. `due_date` is a UTC `yyyy-MM-dd` calendar day; `TaskItem.dueDate` stores it as 00:00 UTC.
`DueDay` (public) maps the local today to that day, snaps picker dates, and counts days between due days.
