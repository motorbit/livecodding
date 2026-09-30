import SwiftUI

/// Typography tokens built on system text styles. They scale with Dynamic Type automatically.
/// Views use only these tokens, never `.font(.system(size:))`.
public extension Font {
    static let dsLargeTitle = Font.largeTitle.weight(.bold)
    static let dsTitle = Font.title2.weight(.semibold)
    static let dsHeadline = Font.headline
    static let dsBody = Font.body
    static let dsBodyEmphasized = Font.body.weight(.semibold)
    static let dsCaption = Font.caption
}
