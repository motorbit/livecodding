import SwiftUI
import UIKit

/// Semantic color tokens defined in code, with light/dark variants resolved by trait collection.
/// Use this instead of an asset catalog when tokens come from a generated source (design tokens
/// JSON → Swift) or when you want diffs in code review.
public extension Color {
    static let dsBrandPrimary = Color(light: 0x1F6FEB, dark: 0x58A6FF)
    static let dsTextPrimary = Color(light: 0x1A1A1A, dark: 0xF2F2F2)
    static let dsTextSecondary = Color(light: 0x5C5C5C, dark: 0xA8A8A8)
    static let dsBackground = Color(light: 0xFFFFFF, dark: 0x000000)
    static let dsSurface = Color(light: 0xF5F5F5, dark: 0x1C1C1E)
    static let dsBorder = Color(light: 0xD0D0D0, dark: 0x3A3A3C)
    static let dsError = Color(light: 0xC62828, dark: 0xFF6B6B)
}

extension Color {
    /// Adaptive color from two 0xRRGGBB values.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
