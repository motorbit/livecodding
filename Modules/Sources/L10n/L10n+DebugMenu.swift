import Foundation

public extension L10n {
    enum DebugMenu {
        public static var title: String {
            String(localized: "debugMenu.title", defaultValue: "Debug Menu", bundle: .module)
        }
        public static var environmentHeader: String {
            String(localized: "debugMenu.environment.header", defaultValue: "Environment", bundle: .module)
        }
        public static var environmentFooter: String {
            String(
                localized: "debugMenu.environment.footer",
                defaultValue: "Switching restarts the app from the start screen.",
                bundle: .module
            )
        }
        public static var environmentLocal: String {
            String(localized: "debugMenu.environment.local", defaultValue: "Local", bundle: .module)
        }
        public static var environmentDev: String {
            String(localized: "debugMenu.environment.dev", defaultValue: "Dev", bundle: .module)
        }
        public static var environmentProd: String {
            String(localized: "debugMenu.environment.prod", defaultValue: "Prod", bundle: .module)
        }
        public static var backendMock: String {
            String(localized: "debugMenu.backend.mock", defaultValue: "In-app mock", bundle: .module)
        }
        public static var backendNotConfigured: String {
            String(localized: "debugMenu.backend.notConfigured", defaultValue: "Not configured", bundle: .module)
        }
    }
}
