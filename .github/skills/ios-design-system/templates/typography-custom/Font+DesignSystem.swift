import CoreText
import Foundation
import SwiftUI

/// Typography tokens using a bundled custom font (`Resources/Fonts/*.ttf|otf`).
///
/// - Fonts in an SPM module aren't registered automatically (no `UIAppFonts`). `FontRegistry`
///   registers them once, lazily, the first time any token is read, so the app shell has nothing
///   to call.
/// - `relativeTo:` keeps Dynamic Type scaling for custom fonts.
/// - Replace `__FontFamily__-Regular` / `__FontFamily__-Bold` with the fonts' PostScript names
///   (Font Book ▸ Info), not the file names.
public extension Font {
    static var dsLargeTitle: Font { custom(.bold, size: 34, relativeTo: .largeTitle) }
    static var dsTitle: Font { custom(.bold, size: 22, relativeTo: .title2) }
    static var dsHeadline: Font { custom(.bold, size: 17, relativeTo: .headline) }
    static var dsBody: Font { custom(.regular, size: 17, relativeTo: .body) }
    static var dsBodyEmphasized: Font { custom(.bold, size: 17, relativeTo: .body) }
    static var dsCaption: Font { custom(.regular, size: 12, relativeTo: .caption) }

    private static func custom(_ face: FontFace, size: CGFloat, relativeTo style: TextStyle) -> Font {
        FontRegistry.registerOnce()
        return .custom(face.rawValue, size: size, relativeTo: style)
    }
}

enum FontFace: String, CaseIterable {
    case regular = "__FontFamily__-Regular"
    case bold = "__FontFamily__-Bold"
}

enum FontRegistry {
    /// `static let` initializers run exactly once and are thread-safe.
    private static let registration: Void = {
        let urls = ["ttf", "otf"].flatMap {
            Bundle.module.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? []
        }
        for url in urls {
            // A "font already registered" error is harmless (e.g. previews); ignore it.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    static func registerOnce() {
        _ = registration
    }
}
