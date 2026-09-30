import Foundation

/// Type-safe access to `Resources/Localizable.xcstrings` in this module.
///
/// - One nested enum per feature (`L10n.Home`), plus `Common` for shared strings.
/// - Keys are `feature.element[.variant]`, e.g. `home.title`, `common.retry`.
/// - Strings are resolved in ViewModels / StateMakers / `State.init` defaults, not in Views.
/// - Interpolated strings use functions; the catalog key contains the format specifier
///   (`"common.itemsCount %lld"`).
public enum L10n {
    public enum Common {
        public static var ok: String { String(localized: "common.ok", bundle: .module) }
        public static var cancel: String { String(localized: "common.cancel", bundle: .module) }
        public static var close: String { String(localized: "common.close", bundle: .module) }
        public static var retry: String { String(localized: "common.retry", bundle: .module) }
        public static var genericError: String { String(localized: "common.error.generic", bundle: .module) }

        public static func itemsCount(_ count: Int) -> String {
            String(localized: "common.itemsCount \(count)", bundle: .module)
        }
    }

    public enum Bootstrap {
        public static var loading: String { String(localized: "bootstrap.loading", bundle: .module) }
    }

    public enum Home {
        public static var title: String { String(localized: "home.title", bundle: .module) }
    }
}
