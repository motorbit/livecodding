<!-- Orchestrator: fill every <…>, then pass the whole text as the sub-agent prompt. -->
You are a worker implementing ONE module of an iOS app in `<Root>`. Other workers are editing other modules in the same working tree right now.

## Task
Implement `<Module>` using the skill `<skill>` with these options: <options from SPEC/PLAN>.
Spec excerpt:
<paste the relevant rows of docs/SPEC.md and docs/PLAN.md: screen description, states, outputs, client contract, DTOs, strings>

## Read first
`<Root>/AGENTS.md` (hard rules), `<Root>/docs/decisions/`, the skill `<skill>`, and the client contracts you depend on: <paths>.

## Allowed paths (write ONLY here)
<list, e.g. Modules/Sources/<Feature>Feature/**, Modules/Tests/<Feature>FeatureTests/**, Modules/Sources/L10n/L10n+<Feature>.swift>

## Forbidden
- Editing `Modules/Package.swift`, `Localizable.xcstrings`, `L10n.swift`, `AppCoordinator/**`, `AGENTS.md`, any other module, or `*.pbxproj`.
- Running `xcodebuild`, `swift build` or `swift test` (the orchestrator runs builds serially).
- Any git command that changes state (add, commit, checkout, stash, reset).
- Inventing navigation beyond the host-scoped push from `ios-feature-module` ▸ Push presentation (deep links, cross-feature `Destination` enums, coordinator-owned stacks); if the screen needs it, stop and say so in the report.

## Conventions for shared things
- Strings: accessors in your own `L10n+<Feature>.swift` as `extension L10n { public enum <Feature> { … } }`, each using `String(localized: "<key>", defaultValue: "<English>", bundle: .module)`.
- Build against client contracts and their `previewValue`; don't implement other modules' live values.

## Final report (exact format)
```
STATUS: done | blocked (<reason>)
FILES: <paths written>
PACKAGE_DEPS: <extra .module(...) or product deps this target needs, or none>
L10N_KEYS:
  <key> = "<base value>"
OUTPUT_EVENTS: <event → expected coordinator action>
NOTES: <assumptions, deviations, anything the orchestrator must know>
```
