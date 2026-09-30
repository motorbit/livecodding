# TaskClient

Domain client for the Task Board. It exposes async CRUD operations over `TaskItem` and `TaskDraft`; the live implementation will be an in-memory actor-backed mock, not the HTTP `NetworkClient`.

## Contract

| Endpoint | Signature |
|---|---|
| `fetchTasks` | `() async throws -> [TaskItem]` |
| `createTask` | `(TaskDraft) async throws -> TaskItem` |
| `updateTask` | `(TaskItem) async throws -> TaskItem` |
| `deleteTask` | `(UUID) async throws -> Void` |

## Values

- `liveValue`: temporary reporting placeholder; replace with the seeded async mock.
- `previewValue`: deterministic sample tasks and in-memory mutations.
- `testValue`: unimplemented.

The mock must preserve insertion order, delay reads 300–800 ms, and fail reads and writes with an injectable approximately 15% failure policy. Tests inject deterministic delay and failure closures.
