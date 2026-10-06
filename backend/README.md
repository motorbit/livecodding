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
make start        # interactive Docker run on Colima (see below)
make run          # in-memory, seeded, :8080
make run-empty    # in-memory, no tasks (--seed=empty)
make run-sqlite   # SQLite at ./tasks.db (DB=…), survives restarts
make run-chaos    # challenge latency + ~15% simulated 500s
make test         # go test -race ./...
make lint         # go vet + gofmt check
make docker-build # image taskapi:dev
make docker-run   # memory store; add ARGS=--store=sqlite to use the taskapi-data volume
```

### `make start` / `scripts/start.sh`

This is the quickest way to run the API in Docker on [Colima](https://github.com/abiosoft/colima):

1. It starts Colima if it isn't running.
2. It asks for the store (`memory`/`sqlite`), the initial data (`filled`/`empty`), chaos (`off`/`on`),
   the log format and the port (default `8080`).
3. It builds `taskapi:dev` if the image is missing (`REBUILD=1` forces a rebuild).
4. It replaces any previous `taskapi` container, and picks the next free port if yours is busy.
5. It waits for `/healthz`, then prints the port on stdout. Everything else goes to stderr.

Preset any answer to skip its prompt:

```bash
PORT=$(STORE=sqlite SEED=empty CHAOS=off LOG_FORMAT=text PORT=8080 ./scripts/start.sh)
curl localhost:$PORT/tasks
```

sqlite data lives on the `taskapi-data` volume. To test the running server, see
[Testing with curl](#testing-with-curl).

### Logs

The server runs in the `taskapi` container and logs one line per request (see
[Logging and privacy](#logging-and-privacy)):

```bash
docker logs -f taskapi              # follow live (Ctrl+C stops following; the server keeps running)
docker logs --tail 50 taskapi       # last 50 lines
docker logs --since 5m taskapi      # last 5 minutes
docker logs taskapi 2>&1 | jq       # pretty-print when started with LOG_FORMAT=json (logs go to stderr)
docker rm -f taskapi                # stop; this also deletes the container's logs
```

Example line (text format):

```
time=2026-10-05T21:12:26.503Z level=INFO msg=request method=GET path=/tasks status=200 duration_ms=0 request_id=c73245ccdead544102b53babafefb525
```

With `make run*` (no Docker), the logs go straight to your terminal.

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
| `POST /tasks` | `201` + `Location: /tasks/{id}`; server assigns `id`, `done=false`. With `Idempotency-Key`, a repeated key returns `200` and the task it created | 400, 404 (key's task deleted), 500 |
| `PUT /tasks/{id}` | `200` with the stored task (full replace, `version` + 1). Optional `If-Match: <version>` | 400, 404, 412 (version changed), 500 |
| `DELETE /tasks/{id}` | `204`, empty body. Optional `If-Match: <version>` | 400 (bad `If-Match`), 404, 412, 500 |
| `GET /healthz` | `200 {"status":"ok"}` (never affected by chaos) | — |

Validation (same as the mock): `title` is trimmed of whitespace and newlines and must not be empty
(the trimmed title is stored). `priority` must be `Low|Medium|High`. `due_date` must be a real
`yyyy-MM-dd` date. `notes` may be empty. Malformed JSON, missing required fields, a body over 1 MiB
or a `PUT` whose body `id` differs from the path `id` → `400`. A path id that isn't a UUID → `404`.

Versions: every task carries `version` (1 on create, +1 on each update; a `version` in a request
body is ignored). `If-Match: 3` or `If-Match: "3"` makes `PUT`/`DELETE` apply only to that version,
otherwise `412`; without the header (or with `*`) the last write wins. SQLite databases created
before versioning get the column on start, with existing tasks at version 1.

Errors are `{"error":"<short message>"}` and never echo input. Every response is
`application/json`. Unknown routes return JSON `404`, and wrong methods return JSON `405` with `Allow`.

### Testing with curl

Start the server (`make start`, or `make run` for port 8080), then paste the blocks below into the
same shell. The examples assume the default `--seed=filled`. `B` uses `$PORT` from the start
script when set, otherwise 8080.

```bash
B=http://localhost:${PORT:-8080}
S1=00000000-0000-0000-0000-000000000001   # seed ids
S2=00000000-0000-0000-0000-000000000002
S3=00000000-0000-0000-0000-000000000003
```

**Happy path**

```bash
curl $B/healthz
# {"status":"ok"}

curl $B/tasks
# [{"id":"00000000-0000-0000-0000-000000000001","title":"Renew domain registration","notes":"Expires end of month","priority":"High","done":false}, …4 tasks]

# Create. The title is trimmed, and the server assigns id and done=false. Keep the id for later.
ID=$(curl -s -X POST $B/tasks -H 'Content-Type: application/json' \
  -d '{"title":"  Pay rent ","notes":"","priority":"High","due_date":"2026-10-31"}' \
  | sed -E 's/.*"id":"([^"]+)".*/\1/'); echo $ID
curl -i -X POST $B/tasks -H 'Content-Type: application/json' -d '{"title":"Water plants","notes":"","priority":"Low"}'
# HTTP/1.1 201 Created, Location: /tasks/<ID>
# {"id":"<ID>","title":"Water plants","notes":"","priority":"Low","done":false}

# Update (full replace): mark done, change the due date. Path ids are case-insensitive.
curl -X PUT $B/tasks/$ID -H 'Content-Type: application/json' \
  -d '{"id":"'$ID'","title":"Pay rent","notes":"paid","priority":"High","done":true,"due_date":"2026-11-30"}'
# {"id":"<ID>","title":"Pay rent","notes":"paid","priority":"High","done":true,"due_date":"2026-11-30"}

# Clear a due date with null (or by omitting it).
curl -X PUT $B/tasks/$S3 -H 'Content-Type: application/json' \
  -d '{"id":"'$S3'","title":"Book dentist","notes":"","priority":"Low","done":false,"due_date":null}'
# {"id":"00000000-0000-0000-0000-000000000003","title":"Book dentist","notes":"","priority":"Low","done":false}

curl -i -X DELETE $B/tasks/$S2
# HTTP/1.1 204 No Content

curl -s $B/tasks | jq -r '.[] | "\(.id)  \(.title)  done=\(.done)  due=\(.due_date // "-")"'
# insertion order: seeds 1, 3, 4, then the created tasks
```

**Errors** (each prints the status after the body)

```bash
W='-> %{http_code}\n'
curl -s -w "$W" -X POST $B/tasks -d '{"title":"  ","notes":"","priority":"Low"}'          # 400 {"error":"title must not be empty"}
curl -s -w "$W" -X POST $B/tasks -d '{"title":"T","notes":"","priority":"Urgent"}'        # 400 {"error":"priority must be Low, Medium or High"}
curl -s -w "$W" -X POST $B/tasks -d '{"title":"T","notes":"","priority":"Low","due_date":"2026-02-30"}'  # 400 {"error":"due_date must be a yyyy-MM-dd date"}
curl -s -w "$W" -X POST $B/tasks -d '{"title":"T","priority":"Low"}'                      # 400 {"error":"malformed JSON body"} (notes is required)
curl -s -w "$W" -X POST $B/tasks -d '{oops'                                               # 400 {"error":"malformed JSON body"}
head -c 1100000 /dev/zero | tr '\0' x | sed 's/.*/{"title":"T","notes":"&","priority":"Low"}/' \
  | curl -s -w "$W" -X POST $B/tasks --data-binary @-                                     # 400 (body over 1 MiB)
curl -s -w "$W" -X PUT $B/tasks/$S1 \
  -d '{"id":"'$S3'","title":"T","notes":"","priority":"Low","done":false}'                 # 400 {"error":"body id must match path id"}
curl -s -w "$W" -X PUT $B/tasks/11111111-2222-4333-8444-555555555555 \
  -d '{"id":"11111111-2222-4333-8444-555555555555","title":"T","notes":"","priority":"Low","done":false}'  # 404 {"error":"task not found"}
curl -s -w "$W" -X DELETE $B/tasks/$S2                                                    # 404 (already deleted)
curl -s -w "$W" -X DELETE $B/tasks/not-a-uuid                                             # 404 {"error":"task not found"}
curl -s -w "$W" -X PATCH $B/tasks                                                         # 405 {"error":"method not allowed"}
curl -s -w "$W" $B/nope                                                                   # 404 {"error":"not found"}
```

**Request IDs**

```bash
curl -s -o /dev/null -D - $B/healthz -H 'X-Request-ID: my-trace-1' | grep -i x-request-id
# X-Request-Id: my-trace-1   (then find it with: docker logs taskapi 2>&1 | grep my-trace-1)
```

**Chaos** (start with `CHAOS=on`, or `make run-chaos`)

```bash
for i in $(seq 20); do curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' $B/tasks; done
# mostly "200 0.3–0.8s", roughly 1 in 7 "500"; /healthz is never delayed or failed
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

## Connecting the iOS app

Implemented in the app's `AppEnvironment` + `TaskClient` modules:

1. **Base URL:** the `dev` environment is `http://localhost:8080` (the simulator reaches the Mac
   there). Change it in `Modules/Sources/AppEnvironment/BuildValues+Generated.swift`, or on CI with
   `API_BASE_URL_DEV=… scripts/generate-build-values.sh`. A device needs the Mac's `*.local` name
   or a tunnel.
2. **Switching:** run `make run`, then in the app tap the floating 🐞 button (bottom-left) → Debug Menu →
   **Dev**. The choice persists; **Local** goes back to the in-app mock.
3. **ATS:** `Config/Debug-Info.plist` adds `NSAllowsLocalNetworking`, wired for the Debug
   configuration only, so Release builds keep full ATS.
4. **Client:** `TaskNetworkClient+HTTP.swift` maps the endpoints with `Endpoint` and decodes through
   `NetworkClient` (off the main actor, logged by its logging middleware). 400 → `.badRequest`,
   404 → `.notFound`, other statuses → `.serverError`, no response → `.transport`.
5. Not done yet: sending `X-Request-ID` from the app so client and server logs correlate.
