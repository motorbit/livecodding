#!/usr/bin/env python3
"""Wire a fresh Xcode "iOS App" project to the local `Modules/` Swift package.

This is the ONLY sanctioned `project.pbxproj` edit in the kit (AGENTS.md R16 exception). The
ios-project-bootstrap skill runs it. It does exactly this, idempotently:

1. Adds `Modules/` to the Project navigator as a folder reference (the "drag Modules into the
   navigator" style). Xcode detects `Modules/Package.swift` and treats it as a local package.
   An existing `XCLocalSwiftPackageReference` to the same folder is converted to that style.
2. Links the `AppCoordinator` product (only) to the app target.
3. Sets the app's build settings: iOS-only destinations (iPhone + iPad), the iOS deployment
   target, Swift 6, MainActor default isolation and Approachable Concurrency. Other targets
   (e.g. unit tests) get the deployment target and Swift version only. The project-level
   iOS deployment target is aligned as well.
4. AppEnvironment (xcconfig + Info.plist option) only: if `Config/Info.plist` exists, sets the app
   target's `INFOPLIST_FILE` to it (the file stays out of every build phase). If
   `Config/Environment.xcconfig` exists, references it in the navigator and assigns it as the base
   configuration of the project's build configurations that have none.
5. Test plan (unless `--no-test-plan`): creates `<App>.xctestplan` next to the project if it's
   missing, filled with every `<package-dir>/Tests/*Tests` target, and adds it to the Project
   navigator. Makes it the default plan of the shared scheme
   `<App>.xcodeproj/xcshareddata/xcschemes/<App>.xcscheme`: creates that scheme if it's missing, or
   migrates its `<Testables>` into the plan. A scheme that already uses another plan is left alone
   (warning). Later module additions are synced by `sync_test_plan.py`.

Safety: refuses to touch a `project.pbxproj` with uncommitted git changes unless
`--allow-dirty`, validates the result with `plutil -lint` and restores the original on failure.
Close the project in Xcode before running it (or let Xcode reload it afterwards).

Usage:
    wire_xcode_project.py <Root>/<App>.xcodeproj [--target <App>] [--package-dir Modules]
                          [--product AppCoordinator] [--config-dir Config] [--ios 16.0] [--swift 6.0]
                          [--no-test-plan] [--allow-dirty] [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import re
import secrets
import subprocess
import sys
import uuid
from pathlib import Path
from xml.dom import minidom

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sync_test_plan import dump, module_test_targets, sync  # noqa: E402

OBJ_INDENT = "\t\t"
FIELD_INDENT = "\t\t\t"
ITEM_INDENT = "\t\t\t\t"


class PbxError(Exception):
    pass


class Pbx:
    """Minimal text-preserving editor for Xcode's old-style plist `project.pbxproj`."""

    def __init__(self, text: str) -> None:
        self.text = text
        self.log: list[str] = []
        self.warnings: list[str] = []
        self.files: dict[Path, str] = {}  # other files to write (test plan, scheme)

    # MARK: - Parsing

    def _match_brace(self, start: int) -> int:
        """Index of the `}` matching the `{` at `start`. Skips quoted strings and comments."""
        depth, i, text = 0, start, self.text
        while i < len(text):
            ch = text[i]
            if ch == '"':
                i += 1
                while text[i] != '"':
                    i += 2 if text[i] == "\\" else 1
            elif text.startswith("/*", i):
                i = text.index("*/", i) + 1
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return i
            i += 1
        raise PbxError("Unbalanced braces in project.pbxproj")

    def object_span(self, oid: str) -> tuple[int, int]:
        """(start, end) of the line(s) `\\t\\t<oid> /* … */ = { … };\\n`, end exclusive."""
        m = re.search(rf"^{OBJ_INDENT}{oid}(?: /\*.*?\*/)? = \{{", self.text, re.M)
        if not m:
            raise PbxError(f"Object {oid} not found")
        close = self._match_brace(m.end() - 1)
        return m.start(), self.text.index("\n", close) + 1

    def object(self, oid: str) -> str:
        start, end = self.object_span(oid)
        return self.text[start:end]

    def replace_object(self, oid: str, new: str) -> None:
        start, end = self.object_span(oid)
        self.text = self.text[:start] + new + self.text[end:]

    def objects_of(self, isa: str) -> list[str]:
        section = re.search(rf"/\* Begin {isa} section \*/\n(.*?)/\* End {isa} section \*/", self.text, re.S)
        if not section:
            return []
        return re.findall(rf"^{OBJ_INDENT}([0-9A-F]{{24}})\b", section.group(1), re.M)

    @staticmethod
    def field(block: str, key: str) -> str | None:
        """A scalar field of an object (multi-line or single-line form), without comments/quotes."""
        m = re.search(rf"(?:^{FIELD_INDENT}|\{{|; ){re.escape(key)} = (.*?);", block, re.M)
        if not m:
            return None
        return re.sub(r"\s*/\*.*?\*/", "", m.group(1)).strip().strip('"')

    @staticmethod
    def _list(block: str, key: str) -> re.Match[str] | None:
        return re.search(rf"^{FIELD_INDENT}{key} = \(\n(.*?)^{FIELD_INDENT}\);", block, re.M | re.S)

    def list_items(self, block: str, key: str) -> list[str]:
        m = self._list(block, key)
        return re.findall(rf"^{ITEM_INDENT}([0-9A-F]{{24}})\b", m.group(1), re.M) if m else []

    def new_id(self) -> str:
        while True:
            oid = secrets.token_hex(12).upper()
            if oid not in self.text:
                return oid

    # MARK: - Mutations

    def add_list_item(self, oid: str, key: str, item: str, comment: str, first: bool = False) -> None:
        block = self.object(oid)
        if item in self.list_items(block, key):
            return
        line = f"{ITEM_INDENT}{item} /* {comment} */,\n"
        m = self._list(block, key)
        if m:
            at = m.start(1) if first else m.end(1)
            block = block[:at] + line + block[at:]
        else:
            name = re.search(rf"^{FIELD_INDENT}name = .*;\n", block, re.M)
            at = name.end() if name else re.search(rf"^{OBJ_INDENT}\}};", block, re.M).start()
            block = block[:at] + f"{FIELD_INDENT}{key} = (\n{line}{FIELD_INDENT});\n" + block[at:]
        self.replace_object(oid, block)

    def remove_list_item(self, oid: str, key: str, item: str) -> None:
        block = self.object(oid)
        new = re.sub(rf"^{ITEM_INDENT}{item}(?: /\*.*?\*/)?,\n", "", block, flags=re.M)
        if new != block:
            self.replace_object(oid, new)

    def add_object(self, isa: str, text: str) -> None:
        end_marker = f"/* End {isa} section */"
        if end_marker in self.text:
            at = self.text.index(end_marker)
            self.text = self.text[:at] + text + self.text[at:]
            return
        section = f"/* Begin {isa} section */\n{text}{end_marker}\n"
        # Keep sections alphabetical, like Xcode does.
        for m in re.finditer(r"^/\* Begin (\w+) section \*/", self.text, re.M):
            if m.group(1) > isa:
                self.text = self.text[: m.start()] + section + "\n" + self.text[m.start():]
                return
        m = re.search(r"^\t\};\n\trootObject = ", self.text, re.M)
        if not m:
            raise PbxError("Cannot find the end of the objects dictionary")
        self.text = self.text[: m.start()] + "\n" + section + self.text[m.start():]

    def remove_object(self, isa: str, oid: str) -> None:
        start, end = self.object_span(oid)
        self.text = self.text[:start] + self.text[end:]
        self.text = re.sub(rf"\n/\* Begin {isa} section \*/\n/\* End {isa} section \*/\n", "", self.text)

    def set_build_setting(self, config_id: str, key: str, value: str | None) -> None:
        """Sets (or, with `value=None`, removes) one build setting in a configuration."""
        block = self.object(config_id)
        m = re.search(rf"^{FIELD_INDENT}buildSettings = \{{\n(.*?)^{FIELD_INDENT}\}};", block, re.M | re.S)
        if not m:
            raise PbxError(f"No buildSettings in {config_id}")
        body = m.group(1)
        existing = re.search(rf"^{ITEM_INDENT}{re.escape(key)} = (.*);\n", body, re.M)
        if value is None:
            if not existing:
                return
            body = body[: existing.start()] + body[existing.end():]
        else:
            rendered = value if re.fullmatch(r"[A-Za-z0-9_./$()]+", value) else f'"{value}"'
            line = f"{ITEM_INDENT}{key} = {rendered};\n"
            if existing:
                if existing.group(0) == line:
                    return
                body = body[: existing.start()] + line + body[existing.end():]
            else:
                keys = re.finditer(rf'^{ITEM_INDENT}"?([A-Za-z0-9_]+)', body, re.M)
                at = next((k.start() for k in keys if k.group(1) > key), len(body))
                body = body[:at] + line + body[at:]
        self.replace_object(config_id, block[: m.start(1)] + body + block[m.end(1):])


def git_is_dirty(path: Path) -> bool | None:
    """True/False for a file in a git work tree; None if it isn't in one."""
    try:
        inside = subprocess.run(
            ["git", "-C", str(path.parent), "rev-parse", "--is-inside-work-tree"],
            capture_output=True, text=True,
        )
        if inside.returncode != 0:
            return None
        status = subprocess.run(
            ["git", "-C", str(path.parent), "status", "--porcelain", "--", path.name],
            capture_output=True, text=True, check=True,
        )
        return bool(status.stdout.strip())
    except FileNotFoundError:
        return None


def wire(pbx: Pbx, args: argparse.Namespace) -> None:
    root = re.search(r"rootObject = ([0-9A-F]{24})", pbx.text)
    if not root:
        raise PbxError("rootObject not found")
    project_id = root.group(1)
    main_group = pbx.field(pbx.object(project_id), "mainGroup")
    if not main_group:
        raise PbxError("mainGroup not found")

    # Resolve the app target.
    targets = {oid: pbx.object(oid) for oid in pbx.list_items(pbx.object(project_id), "targets")}
    apps = {
        oid: block for oid, block in targets.items()
        if pbx.field(block, "productType") == "com.apple.product-type.application"
        and (args.target is None or pbx.field(block, "name") == args.target)
    }
    if len(apps) != 1:
        names = [pbx.field(b, "name") for b in targets.values()]
        raise PbxError(f"Expected exactly one app target (use --target). Targets: {names}")
    app_id = next(iter(apps))
    app_name = pbx.field(apps[app_id], "name")

    # 1. Modules as a navigator folder reference. Convert an XCLocalSwiftPackageReference to it.
    for ref in pbx.objects_of("XCLocalSwiftPackageReference"):
        if pbx.field(pbx.object(ref), "relativePath") != args.package_dir:
            continue
        pbx.remove_list_item(project_id, "packageReferences", ref)
        pbx.remove_object("XCLocalSwiftPackageReference", ref)
        for dep in pbx.objects_of("XCSwiftPackageProductDependency"):
            block = pbx.object(dep)
            cleaned = re.sub(rf"^{FIELD_INDENT}package = {ref}(?: /\*.*?\*/)?;\n", "", block, flags=re.M)
            if cleaned != block:
                pbx.replace_object(dep, cleaned)
        pbx.log.append(f"converted the '{args.package_dir}' local package reference to a folder reference")
    project = pbx.object(project_id)
    empty_refs = re.compile(rf"^{FIELD_INDENT}packageReferences = \(\n{FIELD_INDENT}\);\n", re.M)
    if empty_refs.search(project):
        pbx.replace_object(project_id, empty_refs.sub("", project))

    folder_ref = next(
        (oid for oid in pbx.objects_of("PBXFileReference")
         if pbx.field(pbx.object(oid), "path") == args.package_dir
         and pbx.field(pbx.object(oid), "lastKnownFileType") == "wrapper"),
        None,
    )
    if not folder_ref:
        folder_ref = pbx.new_id()
        pbx.add_object(
            "PBXFileReference",
            f"{OBJ_INDENT}{folder_ref} /* {args.package_dir} */ = {{isa = PBXFileReference; "
            f'lastKnownFileType = wrapper; path = {args.package_dir}; sourceTree = "<group>"; }};\n',
        )
    if folder_ref not in pbx.list_items(pbx.object(main_group), "children"):
        pbx.add_list_item(main_group, "children", folder_ref, args.package_dir, first=True)
        pbx.log.append(f"added the '{args.package_dir}' folder to the Project navigator")

    # 2. Link the product to the app target.
    product_dep = next(
        (oid for oid in pbx.objects_of("XCSwiftPackageProductDependency")
         if pbx.field(pbx.object(oid), "productName") == args.product),
        None,
    )
    if not product_dep:
        product_dep = pbx.new_id()
        pbx.add_object(
            "XCSwiftPackageProductDependency",
            f"{OBJ_INDENT}{product_dep} /* {args.product} */ = {{\n"
            f"{FIELD_INDENT}isa = XCSwiftPackageProductDependency;\n"
            f"{FIELD_INDENT}productName = {args.product};\n"
            f"{OBJ_INDENT}}};\n",
        )
    if product_dep not in pbx.list_items(pbx.object(app_id), "packageProductDependencies"):
        pbx.add_list_item(app_id, "packageProductDependencies", product_dep, args.product)
        pbx.log.append(f"linked {args.product} to target '{app_name}'")

    frameworks = next(
        (oid for oid in pbx.list_items(pbx.object(app_id), "buildPhases")
         if pbx.field(pbx.object(oid), "isa") == "PBXFrameworksBuildPhase"),
        None,
    )
    if not frameworks:
        raise PbxError(f"Target '{app_name}' has no Frameworks build phase")
    build_file = next(
        (oid for oid in pbx.objects_of("PBXBuildFile")
         if pbx.field(pbx.object(oid), "productRef") == product_dep),
        None,
    )
    if not build_file:
        build_file = pbx.new_id()
        pbx.add_object(
            "PBXBuildFile",
            f"{OBJ_INDENT}{build_file} /* {args.product} in Frameworks */ = {{isa = PBXBuildFile; "
            f"productRef = {product_dep} /* {args.product} */; }};\n",
        )
    if build_file not in pbx.list_items(pbx.object(frameworks), "files"):
        pbx.add_list_item(frameworks, "files", build_file, f"{args.product} in Frameworks")

    # 3. Build settings.
    before = pbx.text
    app_settings: dict[str, str | None] = {
        "IPHONEOS_DEPLOYMENT_TARGET": args.ios,
        "SWIFT_VERSION": args.swift,
        "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
        "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
        "SDKROOT": "iphoneos",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "TARGETED_DEVICE_FAMILY": "1,2",
        "SUPPORTS_MACCATALYST": "NO",
        "MACOSX_DEPLOYMENT_TARGET": None,
        "XROS_DEPLOYMENT_TARGET": None,
    }
    other_settings: dict[str, str | None] = {
        "IPHONEOS_DEPLOYMENT_TARGET": args.ios,
        "SWIFT_VERSION": args.swift,
    }
    for oid, block in targets.items():
        settings = app_settings if oid == app_id else other_settings
        config_list = pbx.field(block, "buildConfigurationList")
        for config in pbx.list_items(pbx.object(config_list), "buildConfigurations"):
            for key, value in settings.items():
                pbx.set_build_setting(config, key, value)
    project_configs = pbx.field(pbx.object(project_id), "buildConfigurationList")
    for config in pbx.list_items(pbx.object(project_configs), "buildConfigurations"):
        pbx.set_build_setting(config, "IPHONEOS_DEPLOYMENT_TARGET", args.ios)
    if pbx.text != before:
        pbx.log.append(
            f"build settings: iOS {args.ios} (project + targets), Swift {args.swift}, iPhone/iPad only, "
            "MainActor default isolation, Approachable Concurrency"
        )

    # 4. AppEnvironment: Info.plist + xcconfig kept in `<Root>/Config/`, outside the app's
    # synchronized folder (otherwise Xcode bundles them: "Multiple commands produce Info.plist").
    project_root = args.xcodeproj.parent
    if (project_root / args.config_dir / "Info.plist").is_file():
        before = pbx.text
        for config in pbx.list_items(pbx.object(pbx.field(apps[app_id], "buildConfigurationList")), "buildConfigurations"):
            pbx.set_build_setting(config, "INFOPLIST_FILE", f"{args.config_dir}/Info.plist")
        if pbx.text != before:
            pbx.log.append(f"set INFOPLIST_FILE = {args.config_dir}/Info.plist on target '{app_name}'")
    xcconfig_path = f"{args.config_dir}/Environment.xcconfig"
    if (project_root / xcconfig_path).is_file():
        xcconfig_ref = next(
            (oid for oid in pbx.objects_of("PBXFileReference")
             if pbx.field(pbx.object(oid), "path") in (xcconfig_path, f'"{xcconfig_path}"')),
            None,
        )
        if not xcconfig_ref:
            xcconfig_ref = pbx.new_id()
            pbx.add_object(
                "PBXFileReference",
                f"{OBJ_INDENT}{xcconfig_ref} /* Environment.xcconfig */ = {{isa = PBXFileReference; "
                f'lastKnownFileType = text.xcconfig; name = Environment.xcconfig; path = {xcconfig_path}; sourceTree = "<group>"; }};\n',
            )
            pbx.add_list_item(main_group, "children", xcconfig_ref, "Environment.xcconfig")
        for config in pbx.list_items(pbx.object(project_configs), "buildConfigurations"):
            block = pbx.object(config)
            if pbx.field(block, "baseConfigurationReference"):
                continue
            pbx.replace_object(config, block.replace(
                f"{FIELD_INDENT}buildSettings = {{",
                f"{FIELD_INDENT}baseConfigurationReference = {xcconfig_ref} /* Environment.xcconfig */;\n"
                f"{FIELD_INDENT}buildSettings = {{",
                1,
            ))
            pbx.log.append(f"assigned Environment.xcconfig to project configuration {pbx.field(block, 'name')}")

    # 5. Test plan + shared scheme.
    if not args.no_test_plan:
        wire_test_plan(pbx, args, main_group, app_id, app_name, apps[app_id])


# MARK: - Test plan / scheme

def wire_test_plan(pbx: Pbx, args: argparse.Namespace, main_group: str, app_id: str, app_name: str,
                   app_block: str) -> None:
    project = args.xcodeproj
    plan_path = project.parent / f"{app_name}.xctestplan"
    plan_ref = f"container:{plan_path.name}"
    plan = json.loads(plan_path.read_text()) if plan_path.is_file() else None
    plan_changed = plan is None
    if plan is None:
        plan = new_plan(project.name, app_id, app_name)
        sync(plan, module_test_targets(project.parent / args.package_dir), prune=False)
        pbx.log.append(f"created {plan_path.name} with {len(plan['testTargets'])} module test target(s)")

    scheme_path = project / "xcshareddata" / "xcschemes" / f"{app_name}.xcscheme"
    if scheme_path.is_file():
        text = scheme_path.read_text(encoding="utf-8")
        current = re.search(r'<TestPlanReference\s+reference\s*=\s*"([^"]+)"', text)
        if current and current.group(1) != plan_ref:
            pbx.warnings.append(f"scheme {scheme_path.name} already uses {current.group(1)}; left unchanged")
        elif not current:
            new, migrated = attach_plan(text, plan_ref)
            known = {t.get("target", {}).get("identifier") for t in plan["testTargets"]}
            for entry in migrated:
                if entry["target"]["identifier"] not in known:
                    plan["testTargets"].insert(0, entry)
                    plan_changed = True
            pbx.files[scheme_path] = new
            pbx.log.append(f"made {plan_path.name} the default test plan of scheme {scheme_path.stem}"
                           + (f" (migrated {len(migrated)} testable(s))" if migrated else ""))
    else:
        product_ref = pbx.field(app_block, "productReference")
        product = pbx.field(pbx.object(product_ref), "path") if product_ref else f"{app_name}.app"
        pbx.files[scheme_path] = new_scheme(app_id, app_name, product, project.name, plan_ref)
        pbx.log.append(f"created shared scheme {scheme_path.stem} using {plan_path.name}")
        user_schemes = list(project.glob(f"xcuserdata/*.xcuserdatad/xcschemes/{app_name}.xcscheme"))
        if user_schemes:
            pbx.warnings.append(f"a personal scheme '{app_name}' also exists ({user_schemes[0]}); delete it in "
                                "Xcode (Manage Schemes) so the shared one is used")
    if plan_changed:
        pbx.files[plan_path] = dump(plan) + "\n"

    has_ref = any(pbx.field(pbx.object(oid), "path") == plan_path.name
                  for oid in pbx.objects_of("PBXFileReference"))
    if not has_ref:
        ref = pbx.new_id()
        pbx.add_object(
            "PBXFileReference",
            f"{OBJ_INDENT}{ref} /* {plan_path.name} */ = {{isa = PBXFileReference; lastKnownFileType = text; "
            f'path = {plan_path.name}; sourceTree = "<group>"; }};\n',
        )
        pbx.add_list_item(main_group, "children", ref, plan_path.name)
        pbx.log.append(f"added {plan_path.name} to the Project navigator")


def new_plan(project_name: str, app_id: str, app_name: str) -> dict:
    return {
        "configurations": [{"id": str(uuid.uuid4()).upper(), "name": "Test Scheme Action", "options": {}}],
        "defaultOptions": {
            "codeCoverage": False,
            "performanceAntipatternCheckerEnabled": True,
            "targetForVariableExpansion": {
                "containerPath": f"container:{project_name}", "identifier": app_id, "name": app_name,
            },
            "testInteropMode": "complete",
        },
        "testTargets": [],
        "version": 1,
    }


def _test_plans_block(plan_ref: str) -> str:
    return ('      <TestPlans>\n         <TestPlanReference\n'
            f'            reference = "{plan_ref}"\n            default = "YES">\n'
            '         </TestPlanReference>\n      </TestPlans>\n')


def _test_action(plan_ref: str) -> str:
    return ('   <TestAction\n      buildConfiguration = "Debug"\n'
            '      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"\n'
            '      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"\n'
            '      shouldUseLaunchSchemeArgsEnv = "YES">\n'
            + _test_plans_block(plan_ref) + '   </TestAction>\n')


def attach_plan(text: str, plan_ref: str) -> tuple[str, list[dict]]:
    """Scheme without a test plan → (scheme using `plan_ref`, its former testables as plan entries)."""
    migrated: list[dict] = []
    testables = re.search(r"^[ \t]*<Testables>\n.*?^[ \t]*</Testables>\n", text, re.M | re.S)
    if testables:
        for ref in re.finditer(r"<TestableReference(.*?)>(.*?)</TestableReference>", testables.group(0), re.S):
            attrs = dict(re.findall(r'(\w+)\s*=\s*"([^"]*)"', ref.group(1) + ref.group(2)))
            entry: dict = {"target": {"containerPath": attrs.get("ReferencedContainer", ""),
                                      "identifier": attrs.get("BlueprintIdentifier", ""),
                                      "name": attrs.get("BlueprintName", "")}}
            if attrs.get("skipped") == "YES":
                entry = {"enabled": False, **entry}
            migrated.append(entry)
        text = text.replace(testables.group(0), "")
    if re.search(r"<TestAction\b[^>]*/>", text):
        text = re.sub(r"^[ \t]*<TestAction\b[^>]*/>\n", lambda m: _test_action(plan_ref), text, count=1, flags=re.M)
    elif "<TestAction" in text:
        text = re.sub(r"(<TestAction\b[^>]*>\n)", lambda m: m.group(1) + _test_plans_block(plan_ref), text, count=1)
    else:
        text = re.sub(r"^([ \t]*<LaunchAction\b)", lambda m: _test_action(plan_ref) + m.group(1),
                      text, count=1, flags=re.M)
    minidom.parseString(text)  # raises on malformed XML before anything is written
    return text, migrated


def new_scheme(app_id: str, app_name: str, product: str, project_name: str, plan_ref: str) -> str:
    def ref(i: str) -> str:
        return (f'{i}<BuildableReference\n{i}   BuildableIdentifier = "primary"\n'
                f'{i}   BlueprintIdentifier = "{app_id}"\n{i}   BuildableName = "{product}"\n'
                f'{i}   BlueprintName = "{app_name}"\n{i}   ReferencedContainer = "container:{project_name}">\n'
                f'{i}</BuildableReference>\n')
    runnable = ('      <BuildableProductRunnable\n         runnableDebuggingMode = "0">\n'
                + ref("         ") + '      </BuildableProductRunnable>\n')
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n<Scheme\n   LastUpgradeVersion = "2600"\n   version = "1.7">\n'
        '   <BuildAction\n      parallelizeBuildables = "YES"\n      buildImplicitDependencies = "YES"\n'
        '      buildArchitectures = "Automatic">\n      <BuildActionEntries>\n'
        '         <BuildActionEntry\n            buildForTesting = "YES"\n            buildForRunning = "YES"\n'
        '            buildForProfiling = "YES"\n            buildForArchiving = "YES"\n'
        '            buildForAnalyzing = "YES">\n'
        + ref("            ")
        + '         </BuildActionEntry>\n      </BuildActionEntries>\n   </BuildAction>\n'
        + _test_action(plan_ref)
        + '   <LaunchAction\n      buildConfiguration = "Debug"\n'
        '      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"\n'
        '      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"\n'
        '      launchStyle = "0"\n      useCustomWorkingDirectory = "NO"\n'
        '      ignoresPersistentStateOnLaunch = "NO"\n      debugDocumentVersioning = "YES"\n'
        '      debugServiceExtension = "internal"\n      allowLocationSimulation = "YES">\n'
        + runnable + '   </LaunchAction>\n'
        '   <ProfileAction\n      buildConfiguration = "Release"\n      shouldUseLaunchSchemeArgsEnv = "YES"\n'
        '      savedToolIdentifier = ""\n      useCustomWorkingDirectory = "NO"\n'
        '      debugDocumentVersioning = "YES">\n'
        + runnable + '   </ProfileAction>\n'
        '   <AnalyzeAction\n      buildConfiguration = "Debug">\n   </AnalyzeAction>\n'
        '   <ArchiveAction\n      buildConfiguration = "Release"\n      revealArchiveInOrganizer = "YES">\n'
        '   </ArchiveAction>\n</Scheme>\n'
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("xcodeproj", type=Path)
    parser.add_argument("--target", help="app target name (default: the only app target)")
    parser.add_argument("--package-dir", default="Modules", help="package folder, relative to the project root")
    parser.add_argument("--product", default="AppCoordinator", help="package product to link to the app")
    parser.add_argument("--config-dir", default="Config", help="folder with Info.plist / Environment.xcconfig (AppEnvironment)")
    parser.add_argument("--ios", default="16.0", help="iOS deployment target")
    parser.add_argument("--swift", default="6.0", help="Swift language version")
    parser.add_argument("--no-test-plan", action="store_true", help="don't create/attach <App>.xctestplan")
    parser.add_argument("--allow-dirty", action="store_true", help="edit even if project.pbxproj has uncommitted changes")
    parser.add_argument("--dry-run", action="store_true", help="print the planned changes without writing")
    args = parser.parse_args()

    pbxproj = args.xcodeproj / "project.pbxproj"
    if not pbxproj.is_file():
        print(f"error: {pbxproj} not found", file=sys.stderr)
        return 1
    if not (args.xcodeproj.parent / args.package_dir / "Package.swift").is_file():
        print(f"error: {args.package_dir}/Package.swift not found next to {args.xcodeproj.name}", file=sys.stderr)
        return 1
    dirty = git_is_dirty(pbxproj)
    if dirty and not (args.allow_dirty or args.dry_run):
        print("error: project.pbxproj has uncommitted changes. Commit/stash them or pass --allow-dirty.", file=sys.stderr)
        return 1

    original = pbxproj.read_text(encoding="utf-8")
    pbx = Pbx(original)
    try:
        wire(pbx, args)
    except PbxError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    for line in pbx.warnings:
        print(f"  ! {line}")
    if pbx.text == original and not pbx.files:
        print("Already wired; nothing to change.")
        return 0
    for line in pbx.log:
        print(f"  • {line}")
    if args.dry_run:
        print("Dry run: nothing written.")
        return 0

    if dirty is None:
        backup = pbxproj.with_name("project.pbxproj.orig")
        backup.write_text(original, encoding="utf-8")
        print(f"Not a git repo: backup written to {backup}")
    pbxproj.write_text(pbx.text, encoding="utf-8")
    lint = subprocess.run(["plutil", "-lint", str(pbxproj)], capture_output=True, text=True)
    if lint.returncode != 0:
        pbxproj.write_text(original, encoding="utf-8")
        print(f"error: the result failed plutil -lint; original restored.\n{lint.stdout}{lint.stderr}", file=sys.stderr)
        return 1
    for path, text in pbx.files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    print(f"Wired {args.xcodeproj.name}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
