# TaskClient

Data layer for the Task Board. Features use only the public `TaskClient` (domain `TaskItem` / `TaskDraft`).

```
Feature VM ──▶ TaskClient (repository) ──▶ TaskNetworkClient (DTOs) ──┬─▶ MockNetworkClient (actor, `local`)
               DTO ↔ domain, error mapping     network boundary          └─▶ HTTP via NetworkClient (`dev`/`prod`)
```

## TaskClient (public)

| Endpoint | Signature |
|---|---|
| `fetchTasks` | `() async throws -> [TaskItem]` |
| `createTask` | `(TaskDraft) async throws -> TaskItem` |
| `updateTask` | `(TaskItem) async throws -> TaskItem` |
| `deleteTask` | `(UUID) async throws -> Void` |

Errors: `TaskClientError.validation` (blank title), `.notFound`, `.unavailable` (server failure, no connection, malformed response or no base URL configured). `CancellationError` passes through.

- `liveValue` / `previewValue`: `TaskClient.repository`, which resolves `\.taskNetworkClient` per call.
- `testValue`: unimplemented. Feature tests override its endpoints.

## TaskNetworkClient (internal)

DTO-level CRUD (`TaskDTO`, `TaskDraftDTO`) throwing `TaskNetworkError` (`.badRequest`, `.notFound`, `.serverError`, `.transport`).

- `liveValue`: `.environmentBacked(mock: .mock(policy: .live))`. On **every call** it reads `\.environmentClient.current().apiBackend`:
  - `.mock` → the shared `MockNetworkClient` (one instance per process, so its state survives switches);
  - `.remote(url)` → `.http(baseURL:)` (`TaskNetworkClient+HTTP.swift`): `GET/POST tasks`, `PUT/DELETE tasks/{id}` through `\.networkClient`, off the main actor. 400 → `.badRequest`, 404 → `.notFound`, other statuses → `.serverError`, no response or undecodable body → `.transport`, cancellation → `CancellationError`;
  - `.notConfigured` → logs and throws `EnvironmentError.apiBaseURLMissing`.
- `previewValue`: `.mock(policy: .instant)` (no latency, no failures).
- `testValue`: unimplemented. Tests opt in with `$0.taskNetworkClient = .mock(policy: …)` or per-endpoint overrides.

## MockNetworkClient

An actor seeded from `Resources/seed-tasks.json` (the challenge examples, stable IDs `…0001`–`…0004`). It resets on every launch. `MockNetworkPolicy.live` delays reads by 300–800 ms and writes by 100–300 ms, and fails about 15 % of calls with `.serverError`. It assigns IDs, trims titles and rejects blank ones (`.badRequest`); unknown IDs give `.notFound`.

## Wire format

`TaskDTO` = `{ id, title, notes, priority: "Low"|"Medium"|"High", done, due_date? }`. `due_date` is a UTC `yyyy-MM-dd` calendar day; `TaskItem.dueDate` stores it as 00:00 UTC.
`DueDay` (public) maps the local today to that day, snaps picker dates, and counts days between due days.
