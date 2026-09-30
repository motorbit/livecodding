import SwiftUI

/// Semantic color tokens backed by `Resources/Colors.xcassets` (light + dark per colorset).
///
/// - Views use only these tokens. No `Color(red:…)`, hex literals or system colors for brand UI.
/// - Name tokens by role (`textSecondary`), not by hue (`grey500`).
/// - The `ds` prefix avoids clashes with SwiftUI's `ShapeStyle.background` and similar names.
/// - Adding a token: create `<name>.colorset` with Any + Dark appearances, then add a line here.
public extension Color {
    static let dsBrandPrimary = Color("brandPrimary", bundle: .module)
    static let dsTextPrimary = Color("textPrimary", bundle: .module)
    static let dsTextSecondary = Color("textSecondary", bundle: .module)
    static let dsBackground = Color("background", bundle: .module)
    static let dsSurface = Color("surface", bundle: .module)
    static let dsBorder = Color("border", bundle: .module)
    static let dsError = Color("error", bundle: .module)
}
