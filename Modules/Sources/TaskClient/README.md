# TaskClient

Data layer for the Task Board. Features use only the public `TaskClient` (domain `TaskItem` / `TaskDraft`).

```
Feature VM ──▶ TaskClient (repository) ──▶ TaskNetworkClient (DTOs) ──┬─▶ MockNetworkClient (actor, `local`)
               DTO ↔ domain, error mapping     network boundary          └─▶ HTTP via NetworkClient (`dev`/`prod`)
               write-through ─────────────▶ TaskCacheClient (GRDB/SQLite, scope = environment)
```

## TaskClient (public)

| Endpoint | Signature |
|---|---|
| `fetchTasks` | `() async throws -> [TaskItem]` (also replaces the cache) |
| `cachedTasks` | `() async throws -> [TaskItem]`: the last known list for the active environment; empty if none |
| `clearCache` | `() async throws -> Void`: empties the cache (environment switch); logs errors (`taskCache.clear`) and rethrows |
| `createTask` | `(TaskDraft) async throws -> TaskItem` |
| `updateTask` | `(TaskItem) async throws -> TaskItem` |
| `deleteTask` | `(UUID) async throws -> Void` |

Errors: `TaskClientError.validation` (blank title), `.notFound`, `.unavailable` (server failure, no connection, malformed response or no base URL configured). `CancellationError` passes through.

- `liveValue` / `previewValue`: `TaskClient.repository`, which resolves `\.taskNetworkClient`, `\.taskCacheClient` and `\.environmentClient` per call. After each successful network call it updates the cache (`replaceAll` / `upsert` / `delete`). The cache scope is read before the network call, so an environment switch mid-request can't write into the new environment's cache. A cache write error is logged (`operation: taskCache.write`) and never fails the call; `cachedTasks` logs read errors (`taskCache.read`) and rethrows. A failed network call leaves the cache untouched.
- `testValue`: unimplemented. Feature tests override its endpoints.

## TaskNetworkClient (internal)

DTO-level CRUD (`TaskDTO`, `TaskDraftDTO`) throwing `TaskNetworkError` (`.badRequest`, `.notFound`, `.serverError`, `.transport`).

- `liveValue`: `.environmentBacked(mock: .mock(policy: .live))`. On **every call** it reads `\.environmentClient.current().apiBackend`:
  - `.mock` → the shared `MockNetworkClient` (one instance per process, so its state survives switches);
  - `.remote(url)` → `.http(baseURL:)` (`TaskNetworkClient+HTTP.swift`): `GET/POST tasks`, `PUT/DELETE tasks/{id}` through `\.networkClient`, off the main actor. 400 → `.badRequest`, 404 → `.notFound`, other statuses → `.serverError`, no response or undecodable body → `.transport`, cancellation → `CancellationError`;
  - `.notConfigured` → logs and throws `EnvironmentError.apiBaseURLMissing`.
- `previewValue`: `.mock(policy: .instant)` (no latency, no failures).
- `testValue`: unimplemented. Tests opt in with `$0.taskNetworkClient = .mock(policy: …)` or per-endpoint overrides.

## TaskCacheClient (internal)

On-disk cache of the last known list, so the board can show tasks before (or without) the network. Not a source of truth: there are no offline writes.

- SQLite through GRDB, `Library/Caches/TaskCache.sqlite` (not backed up; the system may purge it, which only costs the first paint). One `task` table keyed by `(scope, id)`, with `position` keeping list order. Ids and priorities are stored as text; a row this version can't read is skipped.
- The whole cache is cleared on every environment switch (`TaskClient.clearCache`, called by `AppCoordinator`). Rows still carry a `scope` (the environment name, read before the network call) and reads filter by the current one, so a response that lands after the switch can't show up in the new environment.
- `TaskCacheDatabase` opens the file and runs `DatabaseMigrator` lazily on first use, off the caller's actor (`@concurrent`). Reads and writes use GRDB's async API.
- Endpoints: `tasks(scope)`, `replaceAll(scope, tasks)`, `upsert(scope, task)` (new tasks append, existing ones keep their position; ignored until `replaceAll` has stored a full list for the scope, tracked in the `cachedScope` table, so a partial list is never shown as the saved one), `delete(scope, id)`, `clear()` (all scopes).
- `liveValue`: the file database. `previewValue` / `.inMemory()`: a private in-memory database. `testValue`: unimplemented.
- Schema changes: add a new migration to `TaskCacheDatabase.migrator`; never edit a shipped one.

## MockNetworkClient

An actor seeded from `Resources/seed-tasks.json` (the challenge examples, stable IDs `…0001`–`…0004`). It resets on every launch. `MockNetworkPolicy.live` delays reads by 300–800 ms and writes by 100–300 ms, and fails about 15 % of calls with `.serverError`. It assigns IDs, trims titles and rejects blank ones (`.badRequest`); unknown IDs give `.notFound`.

## Wire format

`TaskDTO` = `{ id, title, notes, priority: "Low"|"Medium"|"High", done, due_date? }`. `due_date` is a UTC `yyyy-MM-dd` calendar day; `TaskItem.dueDate` stores it as 00:00 UTC.
`DueDay` (public) maps the local today to that day, snaps picker dates, and counts days between due days.
