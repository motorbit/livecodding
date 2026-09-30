# DesignSystem

Shared semantic UI tokens for colors, typography, spacing, corner radii and basic components.

## Tokens

| Group | Examples | Source |
|---|---|---|
| Colors | `Color.dsBrandPrimary`, `Color.dsTextPrimary`, `Color.dsBackground` | `Resources/Colors.xcassets` |
| Typography | `.dsTitle`, `.dsBody`, `.dsCaption` | System text styles |
| Spacing | `.xs`, `.sm`, `.md`, `.lg`, `.xl` | 4-point spacing scale |
| Components | `.buttonStyle(.dsPrimary)`, `DSDivider` | Stateless SwiftUI components |

## Adding a color token

Create a colorset in `Resources/Colors.xcassets` with Any and Dark appearances, then add its semantic accessor to `Color+DesignSystem.swift`. Views should use these tokens rather than literal colors or spacing values.
