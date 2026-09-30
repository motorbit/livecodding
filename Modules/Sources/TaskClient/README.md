# TaskClient

Data layer for the Task Board. Features use only the public `TaskClient` (domain `TaskItem` / `TaskDraft`).

```
Feature VM ──▶ TaskClient (repository) ──▶ TaskNetworkClient (DTOs) ──▶ MockNetworkClient (actor)
               DTO ↔ domain, error mapping     network boundary            in-memory "backend"
```

## TaskClient (public)

| Endpoint | Signature |
|---|---|
| `fetchTasks` | `() async throws -> [TaskItem]` |
| `createTask` | `(TaskDraft) async throws -> TaskItem` |
| `updateTask` | `(TaskItem) async throws -> TaskItem` |
| `deleteTask` | `(UUID) async throws -> Void` |

Errors: `TaskClientError.validation` (blank title), `.notFound`, `.unavailable` (server failure or malformed response). `CancellationError` passes through.

- `liveValue` / `previewValue`: `TaskClient.repository`, which resolves `\.taskNetworkClient` per call.
- `testValue`: unimplemented. Feature tests override its endpoints.

## TaskNetworkClient (internal)

DTO-level CRUD (`TaskDTO`, `TaskDraftDTO`) throwing `TaskNetworkError` (`.badRequest`, `.notFound`, `.serverError`).

- `liveValue`: `.mock(policy: .live)`. **Replace this to talk to a real backend.** Nothing else changes.
- `previewValue`: `.mock(policy: .instant)` (no latency, no failures).
- `testValue`: unimplemented. Tests opt in with `$0.taskNetworkClient = .mock(policy: …)` or per-endpoint overrides.

## MockNetworkClient

An actor seeded from `Resources/seed-tasks.json` (the challenge examples, stable IDs `…0001`–`…0004`). It resets on every launch. `MockNetworkPolicy.live` delays reads by 300–800 ms and writes by 100–300 ms, and fails about 15 % of calls with `.serverError`. It assigns IDs, trims titles and rejects blank ones (`.badRequest`); unknown IDs give `.notFound`.

## Wire format

`TaskDTO` = `{ id, title, notes, priority: "Low"|"Medium"|"High", done, due_date? }`. `due_date` is a UTC `yyyy-MM-dd` calendar day; `TaskItem.dueDate` stores it as 00:00 UTC.
