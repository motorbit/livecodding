# L10n

Holds the String Catalog (`Resources/Localizable.xcstrings`) and the typed accessors in `L10n.swift`.

## Rules

- All user-facing text comes from here. Never hardcode strings in feature modules.
- Resolve strings in the ViewModel, a StateMaker or `State.init` defaults. Views render `state` values.
- Key format is `feature.element[.variant]`. Shared strings go under `common.*`.
- Add the catalog entry and the accessor in the same change. Delete both when a string is no longer used.
- Handle plurals with catalog variations, not with `if count == 1` in code.

## Isolation

This module is **nonisolated** (a leaf with no default MainActor isolation). ViewModels, StateMakers and clients can all read strings.

## Adding a string

1. Add `"feature.key"` to `Localizable.xcstrings`. Xcode's catalog editor also works.
2. Add `public static var key: String { String(localized: "feature.key", bundle: .module) }` under the feature enum.
3. For arguments, add a function whose key contains the format specifier (`"feature.key %@"`).
