import CoreGraphics

/// Spacing scale (4-pt grid). Usage: `.padding(.horizontal, .md)`, `VStack(spacing: .sm)`.
public extension CGFloat {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

/// Corner radii. Usage: `.clipShape(.rect(cornerRadius: CornerRadius.md))`.
public enum CornerRadius {
    public static let sm: CGFloat = 4
    public static let md: CGFloat = 8
    public static let lg: CGFloat = 12
    public static let xl: CGFloat = 24
}

/// Minimum interactive size (Apple HIG: 44×44 pt).
public enum HitTarget {
    public static let minimum: CGFloat = 44
}
