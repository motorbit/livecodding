---
name: ios-design-system
description: Creates a DesignSystem SwiftUI module with a selectable set of parts. Colors come from an asset catalog or code, both with light/dark variants. Typography uses system text styles or a custom font with registration and Dynamic Type. Spacing/radius tokens and basic components are also available. Use when the user says "design system", "colors", "brand font", "typography", "spacing tokens", "dark mode colors" or "button style".
---

# iOS design system

## Purpose

This skill creates `Modules/Sources/DesignSystem/`, a UI module with MainActor default isolation, so that feature Views use **semantic tokens only**. It applies only the selected parts.

**ios-project-bootstrap always runs this skill**: DesignSystem exists in every project, even with a single feature (the AGENTS.md R15 exception). Bootstrap uses all parts (asset colors, system typography, tokens, components) unless the user asks for others. Its `Package.swift` template already declares the `designSystem` target, so step 5 only adjusts `resources:`.

## Inputs / Options

| Group | Choice | Template(s) |
|---|---|---|
| Colors | `assets`: asset catalog, light/dark per colorset (default) | `colors-assets/Color+DesignSystem.swift`, `colors-assets/Colors.xcassets/**` → `Resources/Colors.xcassets` |
| | `code`: adaptive `UIColor` in Swift | `colors-code/Color+DesignSystem.swift` |
| | `none` | — |
| Typography | `system`: text styles (default) | `typography-system/Font+DesignSystem.swift` |
| | `custom`: bundled font + registration | `typography-custom/Font+DesignSystem.swift`, and the user's `.ttf/.otf` → `Resources/Fonts/` |
| | `none` | — |
| Tokens | spacing + corner radius + hit target (yes/no, default yes) | `tokens/DesignTokens.swift` |
| Components | `DSPrimaryButtonStyle`, `DSDivider` (yes/no) | `components/DSComponents.swift`, which needs colors + typography + tokens |

**If the user didn't specify the options, ask one multi-choice question:** "DesignSystem: Colors [asset catalog] [code] [none]; Typography [system] [custom font] [none]; [spacing/radius tokens]; [basic components]". If they pick `custom`, also ask for the font family and file names, and for the brand colors (light/dark hex) if they have them.

## Steps

1. **Resolve the options.** Check the dependencies: components require a colors choice other than `none`, a typography choice other than `none`, and tokens.
2. **Colors:**
   - *assets*: copy `colors-assets/Colors.xcassets` → `Modules/Sources/DesignSystem/Resources/Colors.xcassets`, and `Color+DesignSystem.swift` → `Sources/DesignSystem/`. Replace the sample hex values in each `Contents.json` with the brand colors. Add or remove colorsets and keep the Swift list in sync.
   - *code*: copy `colors-code/Color+DesignSystem.swift` and edit the hex pairs.
3. **Typography:**
   - *system*: copy `typography-system/Font+DesignSystem.swift`.
   - *custom*: copy `typography-custom/Font+DesignSystem.swift`. Put the font files in `Sources/DesignSystem/Resources/Fonts/`. Replace `__FontFamily__-Regular/-Bold` with the **PostScript names**, and adjust the sizes. Add more `FontFace` cases if needed. Tell the user to check the font license allows app embedding.
4. **Tokens / components:** copy the selected files.
5. **Package.swift:** merge `templates/Package.snippet.swift` (skip the parts that are already declared).
   - Keep `resources:` only if `Resources/` exists (assets or custom font). Otherwise delete the `>>> resources` block.
   - Remove the marker lines in every case.
6. **Adopt the tokens:** add `.module(.designSystem)` to the features that render UI. Replace literal colors, fonts and paddings in the existing Views with tokens, e.g. `.foregroundStyle(Color.dsTextPrimary)`, `.font(.dsBody)`, `.padding(.md)`.
7. **Write `Sources/DesignSystem/README.md`:** a token table and "how to add a token".

## Rules / Checklist

- Views use tokens only: no hex/RGB literals, no `.system(size:)`, no magic paddings.
- Name colors by role (`dsTextSecondary`), never by hue. Every color has a dark variant.
- Custom fonts use `Font.custom(_:size:relativeTo:)` so Dynamic Type still scales them. Registration is lazy and once-only, inside the module, and the app shell calls nothing.
- Components are small, stateless and accessible:
  - interactive elements are at least 44 pt,
  - disabled state is visible,
  - decorative views use `.accessibilityHidden(true)`.
- DesignSystem has no business logic, dependencies or L10n. Labels come from callers.
- It's a UI module (`uiModule`), so its static tokens are MainActor-isolated. Use them in Views only.

## Done criteria

- Only the selected parts exist, and `Package.swift` has `resources:` only when needed.
- The Swift color list matches the colorsets (assets option), and `grep -rn "__FontFamily__" Modules` returns nothing (custom font option).
- The previews in `DSComponents.swift` render in light and dark (the user checks this in Xcode).
- **Don't run `xcodebuild`** unless asked.
