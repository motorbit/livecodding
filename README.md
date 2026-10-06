# livecodding — Task Board (iOS)

A small SwiftUI **Task Board** built for an AI-assisted live-coding challenge. The full brief is in
[`docs/CHALLENGE.md`](docs/CHALLENGE.md).

> [!IMPORTANT]
> **The live-coding session ended at `3ad051a` — `chore(L10n): add Task Board strings` (2026-09-30 16:47 +0300, PR #12).**
> Everything after that commit (PR #13 onwards) was done after the session, to align the project with the full brief and add stretch goals.

> [!TIP]
> **Reviewing the history:** every commit landed through its own pull request with a description of what
> changed and why — see [closed PRs](https://github.com/motorbit/livecodding/pulls?q=is%3Apr+is%3Aclosed+sort%3Acreated-asc)
> (#1–#12 live session, #13+ follow-ups). Reading them in order is the easiest way to review the work step by step.

## Stack

- Swift 6.2 (Swift 6 language mode), SwiftUI, Swift Concurrency; deployment target **iOS 17.0** (satisfies "iOS 16+").
- Thin app shell + local SPM package `Modules/`, one module per feature/client.
- Event-driven MVVM, root `AppCoordinator`, DI with [swift-dependencies](https://github.com/pointfreeco/swift-dependencies), Swift Testing.
- Rules and module map: [`AGENTS.md`](AGENTS.md) · spec: [`docs/SPEC.md`](docs/SPEC.md) · plan: [`docs/PLAN.md`](docs/PLAN.md) · decisions: [`docs/decisions/`](docs/decisions/).
- Architecture overview (layers, data flow, trade-offs, evolution): [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

```
TaskBoardFeature ─┬─ AddTaskFeature
                  └─ TaskDetailFeature
        │
   TaskClient (repository: domain models, error mapping)
        │
   TaskNetworkClient (DTO boundary; liveValue picks the backend per call from AppEnvironment)
        │
        ├─ local: MockNetworkClient (actor: latency, ~15 % failures, seed-tasks.json)
        └─ dev / prod: HTTP over NetworkClient → backend/ (Go)
```

## Run

- Open `livecodding.xcodeproj`, scheme **livecodding**, any iOS 17+ simulator.
- The app starts on the **local** environment (in-app mock, no server needed). To use the Go
  backend: `cd backend && make run`, then tap the floating 🐞 button (bottom-left) to open the
  **Debug Menu** and pick **Dev** (`http://localhost:8080`). Base URLs live in
  [`BuildValues+Generated.swift`](Modules/Sources/AppEnvironment/BuildValues+Generated.swift);
  CI regenerates it with `scripts/generate-build-values.sh` (see
  [AppEnvironment](Modules/Sources/AppEnvironment/README.md)).
- Package tests (from `Modules/`):
  `xcodebuild test -scheme Modules-Package -destination 'platform=iOS Simulator,name=<Simulator>'`

## Status against the brief

### Live session (up to `3ad051a`, 16:47)

- ✅ Modular project setup, spec and plan, Task Board contracts
- ✅ Task list with priority badge and completion toggle; loading / empty / error states
- ✅ Add task sheet (title required, notes, Low/Medium/High)
- ✅ Detail / edit with Save, delete with confirmation, unsaved-changes discard prompt
- ✅ Coordinator routing and localized strings
- ✅ Mock network layer — async in-memory service (300–800 ms reads, ~15 % failures); the separate
  DTO / network client split was a later refactor (PRs #15–16)

### After the session

**Core**

- ✅ 1. Task list — scrollable `List`, title, priority indicator, completion toggle
- ✅ 2. Add task — title (required, trimmed and validated), optional notes, priority
- ✅ 3. Complete & delete — optimistic toggle with rollback and row Retry; delete from detail and by swipe
- ✅ 4. Detail / edit screen
- ✅ 5. Own mock network layer — `MockNetworkClient` actor behind a DTO client and a repository
- ✅ 6. Loading, empty and error states (+ reload banner keeping content, no-results state)

**Mock network behaviour**

- ✅ Read delay 300–800 ms (writes 100–300 ms)
- ✅ ~15 % failures on loads and saves
- ✅ `async throws` API; exact seed data from `seed-tasks.json`

**Stretch goals**

- ✅ Search / filter by title (case- and diacritic-insensitive)
- ✅ Sort by priority or completion status (stable)
- ✅ Swipe-to-delete with undo (4 s window, VoiceOver announcement)
- ✅ Due dates with relative formatting ("Due tomorrow", "Overdue by 2 days")
- ⚠️ Theming and dark mode — dark mode via DesignSystem asset colors; no custom themes
- ⬜ Preserve UI state across scene / process recreation

**Quality**

- ✅ 186 Swift Testing tests; deterministic clock, latency and failure injection (no `Task.sleep`)
- ✅ Async-race protection (stored tasks, generation counters, restart of stale loads)
- ✅ Two code reviews against the brief; findings fixed in PR #22

## Known issues

None open. Fixed in PR #24: adding a task after the initial load failed used to show only the new
task with no error or Retry; the board now reloads the list after such a create and shows the
reload banner (with Retry) if that load fails too.

## TODO

- [x] Fix the add-after-failed-load issue (PR #24).
- [ ] Preserve UI state across scene / process recreation — `@SceneStorage` for search text, sort
      order and the open detail task ID, re-resolved after the list loads.
- [ ] Theming — theme selection on top of the existing DesignSystem color tokens.

## Possible improvements

Ideas that follow from the brief's "treat it like the start of a real product":

- ✅ **[Backend in Go](backend/README.md)** — implemented: a small REST service (`GET/POST /tasks`,
  `PUT/DELETE /tasks/{id}`) with the same `TaskDTO` JSON contract. The app talks to it in the
  **dev** environment (Debug Menu); the repository and features are unchanged.
- ✅ **Persistence / caching** — implemented: an on-disk SQLite cache (GRDB) behind `TaskClient`,
  cleared on every environment switch. The board shows cached tasks first, refreshes from the network, and keeps
  the cached list with a "Showing saved tasks" banner when the server can't be reached.
- ✅ **Optimistic completion**: the checkmark toggles at once and rolls back with an inline error if the
  save fails.
- ✅ **Offline changes and sync**: when the server can't be reached, create/edit/complete/delete still
  work. Changes are queued in SQLite and sent before the next load (Retry, pull-to-refresh, or automatically
  when the network comes back). Unsynced rows show a badge, and a banner says "N changes waiting to sync".
  Conflicts: the server wins. A queued edit or delete of a task that changed on the server meanwhile
  is dropped (`If-Match` / `412`), and a banner says how many offline changes weren't applied. A
  change the server refuses is dropped too.
- **Live updates** — expose changes as an `AsyncStream` (the brief's alternative API shape) so
  several screens stay in sync without manual list patching.
- **More filters** — completed/incomplete, overdue, due this week.
- **UI tests and snapshot tests** for states (loading, empty, error, long titles, Dynamic Type, dark mode).
- **CI** — GitHub Actions running package tests and the app build on every PR.
