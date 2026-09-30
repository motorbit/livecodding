import Foundation

/// Build values read from the app's Info.plist, which gets them from `Environment.xcconfig`
/// build settings. The keys must match `Info.plist` in this option.
extension BuildValues {
    public static let current = BuildValues(infoDictionary: Bundle.main.infoDictionary ?? [:])

    enum InfoKey {
        static let environment = "AppEnvironment"
        static let apiBaseHostProd = "ApiBaseHostProd"
        static let apiBaseHostNonProd = "ApiBaseHostNonProd"
    }

    /// Parses the Info.plist values. Missing or invalid values fall back to nonProd, and a debug
    /// build fails loudly (`assertionFailure`) so misconfiguration is caught early.
    init(infoDictionary: [String: Any]) {
        func host(_ key: String) -> URL? {
            (infoDictionary[key] as? String).flatMap { URL(string: "https://\($0)") }
        }
        let environment: AppEnvironment
        if let raw = infoDictionary[InfoKey.environment] as? String, let parsed = AppEnvironment(rawValue: raw) {
            environment = parsed
        } else {
            assertionFailure("Info.plist \(InfoKey.environment) is missing or invalid")
            environment = .nonProd
        }

        var configs: [AppEnvironment: EnvironmentConfig] = [:]
        if let prod = host(InfoKey.apiBaseHostProd) {
            configs[.prod] = EnvironmentConfig(environment: .prod, apiBaseURL: prod)
        }
        if let nonProd = host(InfoKey.apiBaseHostNonProd) {
            configs[.nonProd] = EnvironmentConfig(environment: .nonProd, apiBaseURL: nonProd)
        }
        self.init(
            defaultEnvironment: environment,
            configs: configs,
            allowsOverride: Self.isDebugBuild || environment != .prod
        )
    }
}
