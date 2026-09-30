#!/usr/bin/env python3
"""Keep the app's .xctestplan in sync with the `Modules/Tests/*Tests` folders.

Usage:
    sync_test_plan.py <Root>/<App>.xctestplan [--modules <Root>/Modules] [--dry-run] [--prune]

Run it after adding (or removing) a module with a test target. It's idempotent:
- appends every missing `Modules/Tests/<Name>Tests` target (`container:Modules`);
- keeps existing entries and their options;
- `--prune` removes `container:Modules` entries whose test folder no longer exists (otherwise
  they're only reported).
Output keeps Xcode's formatting (2-space JSON with `" : "`), so there's no diff churn.

It never creates the plan. `wire_xcode_project.py` (ios-project-bootstrap step 9) creates it,
attaches it to the shared app scheme and adds it to the Project navigator.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

CONTAINER = "container:Modules"


def dump(value, indent: int = 0) -> str:
    """JSON in Xcode's .xctestplan style."""
    pad, inner = "  " * indent, "  " * (indent + 1)
    if isinstance(value, dict):
        if not value:
            return "{\n\n" + pad + "}"
        items = [f"{inner}{json.dumps(k)} : {dump(v, indent + 1)}" for k, v in value.items()]
        return "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(value, list):
        if not value:
            return "[\n\n" + pad + "]"
        return "[\n" + ",\n".join(inner + dump(v, indent + 1) for v in value) + "\n" + pad + "]"
    return json.dumps(value, ensure_ascii=False)


def module_test_targets(modules: Path) -> list[str]:
    tests = modules / "Tests"
    if not tests.is_dir():
        return []
    return sorted(
        d.name for d in tests.iterdir()
        if d.is_dir() and d.name.endswith("Tests") and any(d.rglob("*.swift"))
    )


def sync(plan: dict, wanted: list[str], prune: bool) -> tuple[list[str], list[str]]:
    """Mutates `plan`. Returns (added, stale) target names."""
    targets = plan.setdefault("testTargets", [])
    present = {t["target"]["name"] for t in targets if t.get("target", {}).get("containerPath") == CONTAINER}
    added = [n for n in wanted if n not in present]
    targets.extend({"target": {"containerPath": CONTAINER, "identifier": n, "name": n}} for n in added)
    stale = sorted(present - set(wanted))
    if prune and stale:
        plan["testTargets"] = [t for t in targets if not (
            t.get("target", {}).get("containerPath") == CONTAINER and t["target"].get("name") in stale)]
    return added, stale


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("plan", type=Path, help="<Root>/<App>.xctestplan")
    parser.add_argument("--modules", type=Path, help="default: <plan dir>/Modules")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--prune", action="store_true")
    args = parser.parse_args()

    if not args.plan.is_file():
        print(f"error: {args.plan} not found. Create it with ios-project-bootstrap's "
              "wire_xcode_project.py <Root>/<App>.xcodeproj (step 9).", file=sys.stderr)
        return 1
    modules = args.modules or args.plan.resolve().parent / "Modules"
    if not (modules / "Tests").is_dir():
        print(f"error: {modules / 'Tests'} not found", file=sys.stderr)
        return 1

    plan = json.loads(args.plan.read_text())
    added, stale = sync(plan, module_test_targets(modules), args.prune)
    for name in added:
        print(f"+ {name}")
    for name in stale:
        print(f"- {name}" if args.prune else
              f"! {name} is in the plan but Modules/Tests/{name} doesn't exist (use --prune to remove)")
    if not added and not (args.prune and stale):
        print("Test plan already in sync; nothing to change.")
        return 0
    if args.dry_run:
        print("(dry run, not written)")
        return 0
    args.plan.write_text(dump(plan) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
