# Task Board API (Go)

A small REST backend for the Task Board iOS app. It speaks **the same JSON contract** as the app's
in-memory `MockNetworkClient` (`Modules/Sources/TaskClient`), so the app can switch
`TaskNetworkClient.liveValue` to HTTP without changing anything above it.

- Go 1.26, standard library only (`net/http` `ServeMux` patterns, `log/slog`), plus the pure-Go
  [`modernc.org/sqlite`](https://pkg.go.dev/modernc.org/sqlite) driver (no CGO).
- Storage: in-memory (default) or SQLite.
- Optional **chaos mode** reproduces the mock's latency and ~15 % failures.
- Contract: [`openapi.yaml`](openapi.yaml) (OpenAPI 3.1).

## Mapping to the iOS DTOs

| iOS (`TaskDTO.swift`) | JSON | Go (`internal/task`) |
|---|---|---|
| `TaskDTO` | `{"id","title","notes","priority","done","due_date"?}` | `task.Task` |
| `TaskDraftDTO` (POST body) | `{"title","notes","priority","due_date"?}` | `task.Draft` |
| `PriorityDTO` | `"Low"` \| `"Medium"` \| `"High"` | `task.Priority` |
| `DueDateFormat` | `"yyyy-MM-dd"`, UTC calendar day | `task.DueDateLayout` |
| `TaskNetworkError.badRequest / .notFound / .serverError` | 400 / 404 / 5xx | handler status codes |

- `due_date` is omitted when absent. Requests may omit it or send `null`.
- IDs are UUIDs, accepted in any letter case and emitted upper-case (like Swift's `uuidString`).
- Non-optional DTO fields are required, as with Swift `Codable`. Unknown keys are ignored.
- Seeds are the 4 challenge tasks from an embedded copy of `seed-tasks.json`, with ids
  `00000000-0000-0000-0000-00000000000N`. A test fails if the copy drifts from the iOS bundle.

## Run, test, lint

```bash
cd backend
make run          # in-memory, seeded, :8080
make run-empty    # in-memory, no tasks (--seed=empty)
make run-sqlite   # SQLite at ./tasks.db (DB=…), survives restarts
make run-chaos    # challenge latency + ~15% simulated 500s
make test         # go test -race ./...
make lint         # go vet + gofmt check
make docker-build # image taskapi:dev
make docker-run   # memory store; add ARGS=--store=sqlite to use the taskapi-data volume
```

Override the port with `PORT=9090`. Pass extra flags with `ARGS="--log-format=json"`.

## Flags

Every flag falls back to an environment variable. Flags win over env.

| Flag | Env | Default | Meaning |
|---|---|---|---|
| `--addr` | `ADDR` | `:8080` | Listen address |
| `--store` | `STORE` | `memory` | `memory` or `sqlite` |
| `--db` | `DB` | `./tasks.db` (`/data/tasks.db` in Docker) | SQLite file path |
| `--read-latency` | `READ_LATENCY` | off | `GET /tasks*` delay band, e.g. `300ms-800ms` or `500ms` |
| `--write-latency` | `WRITE_LATENCY` | off | `POST`/`PUT`/`DELETE` delay band, e.g. `100ms-300ms` |
| `--failure-rate` | `FAILURE_RATE` | `0` | Probability (0…1) of `500 {"error":"simulated failure"}` |
| `--seed` | `SEED` | `filled` | Initial data: `filled` (the 4 challenge tasks) or `empty` |
| `--log-format` | `LOG_FORMAT` | `text` | `text` or `json` (`slog`) |

## API

| Method + path | Success | Errors |
|---|---|---|
| `GET /tasks` | `200`, array in insertion order | 500 |
| `POST /tasks` | `201` + `Location: /tasks/{id}`; server assigns `id`, `done=false` | 400, 500 |
| `PUT /tasks/{id}` | `200` with the stored task (full replace) | 400, 404, 500 |
| `DELETE /tasks/{id}` | `204`, empty body | 404, 500 |
| `GET /healthz` | `200 {"status":"ok"}` (never affected by chaos) | — |

Validation (same as the mock): `title` is trimmed of whitespace and newlines and must not be empty
(the trimmed title is stored). `priority` must be `Low|Medium|High`. `due_date` must be a real
`yyyy-MM-dd` date. `notes` may be empty. Malformed JSON, missing required fields, a body over 1 MiB
or a `PUT` whose body `id` differs from the path `id` → `400`. A path id that isn't a UUID → `404`.

Errors are `{"error":"<short message>"}` and never echo input. Every response is
`application/json`. Unknown routes return JSON `404`, and wrong methods return JSON `405` with `Allow`.

### curl examples

```bash
B=http://localhost:8080

curl $B/healthz
# {"status":"ok"}

curl $B/tasks
# [{"id":"00000000-0000-0000-0000-000000000001","title":"Renew domain registration","notes":"Expires end of month","priority":"High","done":false}, …]

curl -i -X POST $B/tasks -H 'Content-Type: application/json' \
  -d '{"title":"  Pay rent ","notes":"","priority":"High","due_date":"2026-10-31"}'
# 201, Location: /tasks/<ID>
# {"id":"<ID>","title":"Pay rent","notes":"","priority":"High","done":false,"due_date":"2026-10-31"}

curl -X PUT $B/tasks/00000000-0000-0000-0000-000000000003 -H 'Content-Type: application/json' \
  -d '{"id":"00000000-0000-0000-0000-000000000003","title":"Book dentist","notes":"","priority":"Low","done":false,"due_date":null}'
# 200 {"id":"00000000-0000-0000-0000-000000000003","title":"Book dentist","notes":"","priority":"Low","done":false}

curl -i -X DELETE $B/tasks/00000000-0000-0000-0000-000000000002
# 204

curl -X POST $B/tasks -d '{"title":"  ","notes":"","priority":"Low"}'          # 400 {"error":"title must not be empty"}
curl -X POST $B/tasks -d '{"title":"T","notes":"","priority":"Urgent"}'        # 400 {"error":"priority must be Low, Medium or High"}
curl -X PUT  $B/tasks/00000000-0000-0000-0000-000000000001 \
  -d '{"id":"00000000-0000-0000-0000-000000000004","title":"T","notes":"","priority":"Low","done":false}'  # 400 {"error":"body id must match path id"}
curl -X DELETE $B/tasks/not-a-uuid                                             # 404 {"error":"task not found"}
```

## Chaos mode

`make run-chaos` mirrors the iOS `MockNetworkPolicy.live`, so loading spinners, retry and error
states behave the same against the real server:

- reads (`GET /tasks`) wait 300–800 ms and writes (`POST`/`PUT`/`DELETE`) wait 100–300 ms, picked uniformly;
- after the delay, ~15 % of requests return `500 {"error":"simulated failure"}` before reaching the handler, so nothing changes;
- only `/tasks` routes are affected, and `/healthz` stays instant;
- the delay stops early if the client cancels the request.

Randomness and sleeping are injectable (`httpapi.Chaos.Rand` / `.Sleep`), so tests are deterministic
and never sleep.

## Logging and privacy

One `slog` line per request: `method`, `path` (never the query string), `status`, `duration_ms`,
`request_id`. Headers, bodies and query values are never logged, matching the iOS logging
middleware's redaction rules. A test enforces this.

- **Request ID:** an incoming `X-Request-ID` (or `X-Correlation-ID`) is honoured when it is ≤ 128 chars
  of `[A-Za-z0-9._-]`. Otherwise a random id is generated. It's echoed in `X-Request-ID`, and also in
  `X-Correlation-ID` when the client sent that header.
- **Panics** return `500 {"error":"internal error"}` and are logged with the request ID and the panic's
  type only.
- **Store failures** return a generic `500` and log the error with the request ID.

## Storage

- **memory**: seeded on start and guarded by a `sync.RWMutex`. Lost on restart.
- **Initial data:** `--seed=filled` (default) starts with the challenge tasks, and `--seed=empty`
  starts with none. With sqlite the flag applies only to an empty table, so it never changes or
  removes existing data.
- **sqlite**: creates the schema on start and seeds (if `--seed=filled`) only when the `tasks` table is empty. Order is
  kept by an `AUTOINCREMENT` `seq` column. It runs in WAL mode with one connection, which avoids
  `SQLITE_BUSY`. Data survives restarts. Note that deleting every task and restarting re-seeds.
- In Docker, the database lives at `/data/tasks.db`. Mount a volume on `/data`:
  `docker run -p 8080:8080 -v taskapi-data:/data taskapi:dev --store=sqlite`.

## Layout

```
cmd/taskapi/        flags/env, wiring, graceful shutdown (SIGINT/SIGTERM, 10 s)
internal/task/      model, validation, ids, JSON decoding
internal/store/     Store interface, memory, sqlite, embedded seeds
internal/httpapi/   routes, handlers, middleware (request ID, access log, recover, chaos)
openapi.yaml        contract; a test checks every registered route is documented
```

## Connecting the iOS app (next step)

Not implemented yet. The plan:

1. **Base URL:** the simulator reaches the Mac at `http://localhost:8080`. A device needs the Mac's
   LAN IP, or a tunnel.
2. **ATS:** plain HTTP needs an App Transport Security exception for local development, e.g.
   `NSAppTransportSecurity` → `NSAllowsLocalNetworking = YES` in the app's Info.plist, limited to
   debug builds.
3. **Client:** implement `TaskNetworkClient.liveValue` as an HTTP client over the existing
   `NetworkClient` module. Use `Endpoint` for `GET/POST /tasks` and `PUT/DELETE /tasks/{id}`, and
   `decode` for `TaskDTO`/`[TaskDTO]`. Map 400 → `.badRequest`, 404 → `.notFound` and 5xx →
   `.serverError`. `TaskClient`, the features and the DTOs stay unchanged. Keep `MockNetworkClient`
   for previews and tests.
4. Optionally send `X-Request-ID` from the app so client and server logs correlate.
