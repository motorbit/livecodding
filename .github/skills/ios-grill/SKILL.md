---
name: ios-grill
description: Interviews the user relentlessly about a short iOS app brief (text, optional screenshots) until every design decision is settled, then writes docs/SPEC.md. Works the decisions as a design tree in rounds, recommends an answer for every question, and looks up facts itself (screenshots, Xcode project, simulators) with sub-agents. Use when the user gives a brief/ТЗ/mockup for a new app or feature, says "grill me", "stress-test the plan", "clarify requirements", or before ios-app-autopilot.
---

# iOS grill (brief → shared understanding → SPEC.md)

Adapted from Matt Pocock's `grilling` skill (github.com/mattpocock/skills), specialized for this kit's iOS architecture.

## Purpose

Turn a short brief (and maybe a screenshot) into a **complete, confirmed spec** before any code is written. Nothing gets silently assumed. The output, `docs/SPEC.md`, is the single input for `ios-app-autopilot` and the other skills.

## How to grill

1. Map the work as a **design tree**: every decision branches into the decisions that hang off it. Start from the seed tree below, then prune branches the brief makes irrelevant and add branches it implies.
2. Work in **rounds**. The **frontier** is every open decision whose prerequisites are settled. Ask the whole frontier in one round. Number the questions and give your recommended answer for each. A question that depends on another question in the same round waits for a later round.
3. **Facts are your job, decisions are the user's.** Never ask the user something you can look up. Dispatch sub-agents in the background for fact-finding (see "Parallel fact-finding"). Only the questions downstream of a running lookup wait; ask the rest now.
4. Recommend answers that follow this kit's `AGENTS.md` hard rules and ADRs. Mark a recommendation "(kit default)" when it simply follows a rule, so the user can answer those in bulk with "defaults".
5. After every round, recompute the frontier. Stop when the frontier is empty: every branch visited, nothing assumed.
6. Write `docs/SPEC.md` (format below), show a short summary, and **ask the user to confirm**. Don't hand off to implementation until they confirm.

Round format:

```
❓ **Q1 — <title>**: <question, with options when they're discrete>

➡️ <recommended answer> [(kit default)]

---

❓ **Q2 — …**
```

Keep each round to the frontier; typically 4–10 questions. If the harness has a structured question tool (e.g. `ask_user`), you may use it for rounds with discrete choices, but keep the numbering and the recommendations.

## Seed design tree (iOS app)

Prune and extend it for the brief. Indentation = dependency.

- **Goal & users**: who, the main job-to-be-done, what "done" means for this iteration (MVP), explicit non-goals.
  - **Screens & flows**: inventory of screens (from the brief/screenshots), the entry screen, the happy path.
    - Per screen: content, user actions, states (loading / empty / error / content), outputs (where each action leads).
    - **Top-level routes vs. embedded/sheets** (coordinator vs. child presentation). A push from a screen uses the kit's **host-scoped NavigationStack** (`ios-feature-module` placement "push"): record the host per pushed screen. Deep links into pushed screens, cross-feature `Destination` enums and coordinator-owned stacks are still **open kit questions**: flag them and ask (don't invent).
  - **Data**: per screen, where the data comes from: static/mock, local persistence, a backend API.
    - Backend: base URL(s), environments (prod/nonProd), auth scheme, API contract available? (OpenAPI/JSON samples) → `ios-network-client` options.
    - Mock-first? (build the UI against a `previewValue`/fake client until the API exists).
    - Persistence: none / UserDefaults / Keychain / SwiftData → `ios-storage` options.
  - **Auth/session**: none / token / third-party SDK. Sign-out behaviour.
- **Look & feel**: `ios-design-system` options. DesignSystem always exists (bootstrap default: asset colors, system typography, tokens, components); settle colors from the screenshot and custom fonts. Dark mode, Dynamic Type, iPhone only or iPad, orientations.
- **Localization**: languages (base language, others now or later).
- **Cross-cutting**: analytics (yes/no, vendor later) → `ios-analytics`; environments/debug override → `ios-app-environment`; logging is always on.
- **Quality**: test depth (VM tests for every feature is the kit default), accessibility baseline, performance constraints.
- **Execution** (for autopilot): may the agent run `xcodebuild`? Which simulator? Commit granularity (per module is the default)? Anything the agent must not touch? Time/credit budget?

## Parallel fact-finding

Start these right away, in the background, while you ask round 1 about goals and scope:

| Lookup | How |
|---|---|
| Screenshot analysis | Sub-agent reads each attached image and returns: screen inventory, UI elements per screen, visible texts (for L10n), color palette (hex), font hints, navigation hints (tab bar, back buttons, sheets) |
| Project facts | App name and bundle id (`*.xcodeproj`, `project.pbxproj` read-only), deployment target, existing `Modules/`, git state (`git status`, `git log --oneline -5`) |
| Toolchain | `xcodebuild -version`, `swift --version`, `xcrun simctl list devices available` (pick the newest iPhone as the default simulator) |
| API contract | If the brief links docs/OpenAPI/JSON samples: summarize endpoints, models, auth |

Use their results to pre-fill recommendations (e.g. "Q: design system? ➡️ yes: 5 brand colors extracted from the screenshot: …").

## Output: `docs/SPEC.md`

```markdown
# <App> — Spec (confirmed <date>)
## Goal, users, MVP scope, non-goals
## Screens
| Screen | Module | Placement (route/embedded/sheet) | Data source | States | Outputs → |
## Data & API        (endpoints, models, auth, environments, mock-first?)
## Persistence       (clients chosen and why)
## Design            (colors, fonts, tokens, components, dark mode, devices)
## Localization
## Cross-cutting     (analytics, environment, logging)
## Kit options       (per skill: the exact options chosen, e.g. ios-network-client: json, endpoint, auth, logging)
## Execution         (xcodebuild allowed?, simulator, commit policy, budget)
## Open / deferred   (anything the user explicitly postponed, incl. deep-link / cross-feature navigation)
## Decision log      (Q# → answer, one line each)
```

## Rules

- Never start implementing during grilling. Writing `docs/SPEC.md` is the only file change (plus a commit, if the project has git).
- Don't ask for facts; don't decide for the user. "Defaults" from the user = accept every "(kit default)" in the current round.
- Don't re-ask settled decisions. If a later answer contradicts an earlier one, point it out and ask which wins.
- Keep the spec concrete: names of modules, routes, clients and options, not prose.

## Done criteria

- The frontier is empty and the user has confirmed the summary.
- `docs/SPEC.md` exists and every section is filled or explicitly "none".
- Every kit skill that will be used has its options recorded in "Kit options".
