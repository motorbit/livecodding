---
name: ios-app-autopilot
description: Autonomously builds a new iOS app from a short brief in an empty Xcode project using this kit. It runs ios-grill (spec), plans a module task graph, bootstraps, scaffolds client contracts, implements clients and features in parallel with sub-agents, integrates routes, runs build/test gates and the ios-reviewer, and commits each step to the local git repo. Use when the user says "build the app from this brief/ТЗ", "autopilot", "make this app", or gives a brief + screenshot right after creating an empty Xcode project.
---

# iOS app autopilot (brief → working modular app)

## Purpose

Take the user from "brief + empty Xcode project" to a building, tested, reviewed app with **one confirmation checkpoint** after the spec and plan. You are the **orchestrator**: you own every shared file, every build and every commit. Sub-agents only write code inside the paths you assign them.

Read first: `AGENTS.md`, `docs/decisions/`, and the skills you'll chain: `ios-grill`, `ios-project-bootstrap`, `ios-dependency-client`, `ios-network-client`, `ios-storage`, `ios-design-system`, `ios-analytics`, `ios-app-environment`, `ios-feature-module`, `ios-coordinator-route`, and the `ios-reviewer` agent.

## Phases

| # | Phase | Mode | Commit |
|---|---|---|---|
| 0 | Preflight | sequential | `chore: prepare repository` (only if something changed) |
| 1 | Grill → `docs/SPEC.md` | interactive (**checkpoint**) | `docs: add app spec` |
| 2 | Plan → `docs/PLAN.md` | sequential, shown with the spec | `docs: add implementation plan` |
| 3 | Bootstrap | sequential | `feat: bootstrap modular app shell` |
| 4 | Contracts & scaffold | sequential | `chore: scaffold modules and client contracts` |
| 5 | Implement | **parallel waves** | one commit per module: `feat(<Module>): …` |
| 6 | Integrate | sequential | `feat(AppCoordinator): wire routes`, `chore(L10n): add strings` |
| 7 | Review & fix | parallel review, sequential fixes | `fix(<Module>): address review` |
| 8 | Report | — | — |

After the checkpoint in phase 1–2, run to the end without asking, unless a **stop condition** fires.

### 0. Preflight

1. Find `<Root>/<App>.xcodeproj`. If it's missing, stop and give the user the Xcode steps from `ios-project-bootstrap` ▸ Preconditions (tick **Create Git repository on my Mac**).
2. Git: if there's no `.git`, run `git init` and commit the Xcode template as `chore: initial Xcode project`. The working tree must be clean; if not, ask whether to commit or stash the user's changes.
3. Ensure `.gitignore` has `xcuserdata/`, `DerivedData/`, `.build/`, `.swiftpm/`, `*.xcresult`.
4. Create `docs/` and `docs/AUTOPILOT.md` (the run log: phase, what was done, build results, problems). Append to it at the end of every phase.

### 1. Grill

Run **ios-grill** on the brief and screenshots. Start its fact-finding sub-agents in the background immediately. The **Execution** branch must settle: may you run `xcodebuild` (default yes in autopilot), which simulator, and the commit policy. Commit the spec after the user confirms.

### 2. Plan

Derive `docs/PLAN.md` from the spec with `templates/PLAN.md`:
- Module list with kind (client / UI) and dependencies.
- **Client contracts**: every `@DependencyClient` struct with its endpoints and DTOs, plus preview/fake data. This is what lets features and clients be built in parallel.
- Task DAG and waves (see "Parallelism"). If the harness has a todo/SQL tool, mirror the DAG there (`todos` + `todo_deps`).
- Show the plan together with the spec summary. This is the single confirmation checkpoint: "Spec + plan OK → I'll run autonomously to the end?"

### 3. Bootstrap

Run **ios-project-bootstrap** non-interactively with the options from `SPEC.md ▸ Kit options` (don't re-ask). Bootstrap always creates DesignSystem (with the spec's parts) and BootstrapFeature. Chain the selected infrastructure skills (environment, analytics, network, storage) here too; they touch `Package.swift` and are quick. Build gate. Commit.

The bootstrap wires `Modules/` into the Xcode project itself (`wire_xcode_project.py`), so there's no manual Xcode step. If the script refuses (dirty `project.pbxproj`, Xcode open), note it in the run log and continue: the package builds and tests through the `Modules-Package` scheme without it.

### 4. Contracts & scaffold (sequential; makes phase 5 conflict-free)

1. Add **every** planned module to `Modules/Package.swift` (Module case, target, test target, dependencies). This is the last time `Package.swift` changes before integration. Once the test folders exist, run `python3 .github/skills/ios-project-bootstrap/scripts/sync_test_plan.py <Root>/<App>.xctestplan` (the orchestrator owns the test plan; workers never touch it).
2. For each domain client: write the interface file (`@DependencyClient` struct, DTOs, `DependencyKey` with `liveValue` = unimplemented placeholder calling `reportIssue`, `previewValue` with fake data, `testValue = Self()`), following `ios-dependency-client`.
3. For each feature: create the folder with a placeholder file so the target exists.
4. Build gate. Commit.

### 5. Implement (parallel waves)

- **Wave A** (in parallel): client live implementations; design-system components if the spec needs custom ones.
- **Wave B** (in parallel, can start together with wave A): feature modules. They depend only on client **contracts** and `previewValue`s, not on live implementations.
- Features that embed another feature go in a later wave than their child.

For each task, start one background sub-agent with `templates/worker-prompt.md`. Run at most **4** at once. When a worker finishes:
1. Check that it touched only its allowed paths (`git status --porcelain`). Revert anything outside them and note it in the run log.
2. Apply the shared-file changes it reported (see "Shared files"), except L10n catalog entries, which are merged in phase 6.
3. Build gate (serially; never two builds at once).
4. Commit its paths: `git add <paths> && git commit -m "feat(<Module>): <summary>"`.

If the build fails because of a worker's module, send the errors back to that worker (multi-turn) or fix them yourself. Allow at most 3 attempts per module, then mark it blocked in the run log and continue with the others.

### 6. Integrate (sequential)

1. For each top-level feature, run **ios-coordinator-route** (AppRoute, AppScreen, `makeScreen`, `didEnter`, `handle`, CoordinatorView), using the output→route mapping from the spec.
2. Merge the reported L10n keys into `Localizable.xcstrings` (base language + the spec's languages).
3. Update `AGENTS.md` ▸ Module map and each module `README.md`.
4. Build gate + full test run. Commit.

### 7. Review & fix

1. In parallel, run the **ios-reviewer** agent once per module (read-only, so parallel is safe) on the files changed since the bootstrap commit. Optionally add a generic code-review / rubber-duck pass.
2. Fix ❌ findings one module at a time (build gate after each), commit per module. Record ⚠️ findings in the run log instead of fixing them.

### 8. Report

Short summary: what was built, the commit list (`git log --oneline`), test results, blocked items, deferred decisions (`SPEC.md ▸ Open`), and any manual Xcode steps still pending (e.g. a skipped wiring script, capabilities).

## Parallelism

What can run in parallel, and why it's safe:

| Work | Parallel? | Why |
|---|---|---|
| Grill fact-finding (screenshots, toolchain, project) | ✅ background | read-only |
| Client live impls + feature modules | ✅ | disjoint folders; features build against contracts |
| Reviews | ✅ | read-only |
| `Package.swift`, `Localizable.xcstrings`, `L10n.swift`, `AppCoordinator/*`, `AGENTS.md` | ❌ orchestrator only | shared files → merge conflicts |
| Builds and tests | ❌ one at a time | shared `.build`/DerivedData locks |
| `git add/commit` | ❌ orchestrator only | one shared index |

All workers share one working tree; the path discipline above is what makes that safe. Use **git worktrees** (one branch per worker, merged by the orchestrator) only if workers must edit shared files, e.g. when extending an existing app with several cross-cutting features.

Harness notes:
- **GitHub Copilot CLI:** start workers with the task/sub-agent tool in background mode (general-purpose agent) and keep working; you're notified when each finishes. `/fleet` enables parallel sub-agent execution, `/autopilot` lets the session continue without prompts, and `/allow-all` (or pre-approved tools) avoids permission stops. Attach screenshots with `@path/to/image.png`.
- **Claude Code:** start several Task sub-agents in one message to run them in parallel. Configure allowed tools in `.claude/settings.json` rather than skipping permissions.

## Shared files

Workers never edit shared files. In their final report they list:
- `Package.swift`: extra dependencies their target needs.
- L10n: new keys with base-language values (`key = "value"`). They write accessors in their own file `Modules/Sources/L10n/L10n+<Feature>.swift` (`extension L10n { public enum <Feature> { … } }`), using `String(localized: "<key>", defaultValue: "<value>", bundle: .module)` so the app shows correct text even before the catalog merge.
- Coordinator: output events and the routes they expect.

## Build gate

From `Modules/`, only if the spec allows `xcodebuild`:

```bash
xcodebuild -scheme Modules-Package -destination 'platform=iOS Simulator,name=<Simulator>' -quiet build-for-testing
xcodebuild -scheme Modules-Package -destination 'platform=iOS Simulator,name=<Simulator>' -quiet test-without-building [-only-testing:<Module>Tests]
```

Summarize failures (first error per file) in the run log. If `xcodebuild` isn't allowed, skip the gates, say so in every commit message body, and list the builds the user must run.

## Stop conditions (ask the user, then continue)

- The spec is contradicted by reality (API differs, a required SDK isn't available).
- A module stays red after 3 fix attempts and other modules depend on it.
- The work needs navigation beyond a host-scoped push (deep links into pushed screens, cross-feature `Destination` enums, a coordinator-owned stack; open kit questions) or anything else the spec marks as deferred.
- A change would need `project.pbxproj` edits (entitlements, capabilities, new targets) beyond the bootstrap's `wire_xcode_project.py`: give manual steps instead.
- Anything destructive to the user's files or git history.

## Rules

- All kit hard rules apply. `xcodebuild` is allowed here only because the spec's Execution section says so.
- Commits are local. Never push, never rewrite history, never commit secrets.
- Keep `docs/AUTOPILOT.md` up to date; it's how the user (or a resumed session) sees where things are.

## Done criteria

- Every module in the plan is implemented, committed and passing tests, or is listed as blocked with the reason.
- `git log` shows one commit per phase/module; `git status` is clean.
- `docs/SPEC.md`, `docs/PLAN.md`, `docs/AUTOPILOT.md` and `AGENTS.md` are up to date.
- The user has the final report and any pending manual Xcode steps.
