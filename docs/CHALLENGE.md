# Live Coding Challenge — iOS (AI-assisted)

## Overview

Build a small **Task Board** app from scratch in a greenfield iOS project. You'll have **60 minutes**. The core feature is meant to be quick — there's a stretch list to keep going if you finish early.

This is an **AI-first** exercise: use whatever AI tooling you normally work with, and please **share your screen and think aloud** as you go. We're interested in how you actually build, not in memorized syntax. Treat it like the start of a real product you'd hand to a team — not a throwaway demo.

## Before we start

Have Xcode and your AI tools installed and working beforehand, with a simulator or device ready — so we don't lose time to setup or a first build.

## Tech

- Swift + SwiftUI, Swift Concurrency (async/await)
- Greenfield: start from an empty project and set it up however you like
- **No backend** — build a mock network layer yourself; how you design the rest of the data layer (repositories, caching, persistence, etc.) is up to you
- Target iOS 16+, single app target / Swift Package is fine

## Scenario

A Task Board lets a user track personal tasks. Build a slice of it: a list of tasks, the ability to add and complete them, and a detail view for editing.

## Core requirements

1. **Task list screen** — a scrollable list of tasks. Each row shows the title, a priority indicator, and a way to mark it complete.
2. **Add a task** — title (required), optional notes, and a priority (Low / Medium / High).
3. **Complete & delete** — toggle a task complete; delete a task.
4. **Detail / edit screen** — tap a task to view and edit its fields.
5. **Build your own mock network layer** — there's no backend, so stand up a fake network/API source yourself that the app talks to. It should behave like a real async API (see below). How you structure everything above it — repositories, caching, persistence — is your call.
6. **State handling** — the list must handle **loading, empty (no tasks), and error** states. The mock network layer simulates latency and occasional failures, so these states are real.

## Mock network layer behavior

- Add an artificial delay (e.g. 300–800 ms) on reads.
- Fail roughly 15% of the time on load/save so error paths actually occur.
- Expose data via `async` functions or an `AsyncStream`.

## Sample seed data

```json
[
  { "title": "Renew domain registration", "notes": "Expires end of month", "priority": "High",   "done": false },
  { "title": "Reply to design feedback",  "notes": "",                      "priority": "Medium", "done": false },
  { "title": "Book dentist",              "notes": "",                      "priority": "Low",    "done": true  },
  { "title": "Migrate the analytics pipeline to the new warehouse and validate dashboards", "notes": "Long one — check layout", "priority": "Medium", "done": false }
]
```

## Stretch goals (optional, any order)

- Search / filter the list by title.
- Sort by priority or by completion status.
- Swipe-to-delete with an undo affordance.
- Preserve UI state across scene / process recreation.
- Due dates with relative formatting.
- Theming and dark-mode support.

## Out of scope

Not required: real networking, authentication, push notifications. On-disk persistence (Core Data / SwiftData) and multiple packages aren't needed either — in-memory is fine. If you make a deliberate choice in any of these areas, just tell us why.

## How we'll run it

- ~5 min to read this and ask questions / sketch a plan.
- ~45 min to build.
- ~10 min to walk us through what you built and what you'd do next.

Stretch goals are genuinely optional — we'd rather see solid, well-reasoned core work than a rushed pile of half-features.
