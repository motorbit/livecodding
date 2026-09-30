import Foundation
import Testing
@testable import AppEnvironment

struct EnvironmentClientTests {
    private let prod = EnvironmentConfig(environment: .prod, apiBaseURL: URL(string: "https://api.example.com")!)
    private let nonProd = EnvironmentConfig(environment: .nonProd, apiBaseURL: URL(string: "https://api.nonprod.example.com")!)

    private func build(default environment: AppEnvironment, allowsOverride: Bool) -> BuildValues {
        BuildValues(defaultEnvironment: environment, configs: [.prod: prod, .nonProd: nonProd], allowsOverride: allowsOverride)
    }

    /// An isolated, empty defaults suite per test.
    private func makeDefaults() -> UserDefaults {
        let name = "EnvironmentClientTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("""
        Given no override,
        When current is read,
        Then the build default is returned
        """)
    func defaultEnvironment() {
        let sut = EnvironmentClient.live(build: build(default: .nonProd, allowsOverride: true), defaults: makeDefaults())

        #expect(sut.current() == nonProd)
    }

    @Test("""
        Given overrides are allowed,
        When an override is set and then cleared,
        Then current follows it and falls back to the default
        """)
    func overrideAllowed() {
        let sut = EnvironmentClient.live(build: build(default: .nonProd, allowsOverride: true), defaults: makeDefaults())

        sut.setOverride(.prod)
        let overridden = sut.current()
        sut.setOverride(nil)

        #expect(overridden == prod)
        #expect(sut.current() == nonProd)
        #expect(sut.selectableEnvironments() == [.prod, .nonProd])
    }

    @Test("""
        Given a prod release build with a stale override stored by a debug build,
        When current is read,
        Then the override is ignored and removed
        """)
    func overrideIgnoredInProdRelease() {
        let defaults = makeDefaults()
        defaults.set(AppEnvironment.nonProd.rawValue, forKey: EnvironmentClient.overrideKey)
        let sut = EnvironmentClient.live(build: build(default: .prod, allowsOverride: false), defaults: defaults)

        #expect(sut.current() == prod)
        #expect(defaults.string(forKey: EnvironmentClient.overrideKey) == nil)
        #expect(sut.selectableEnvironments().isEmpty)
    }

    // >>> option:buildtime-infoplist
    @Test("""
        Given Info.plist values from the xcconfig,
        When build values are parsed,
        Then hosts become https URLs and the environment is read
        """)
    func parsesInfoDictionary() {
        let values = BuildValues(infoDictionary: [
            "AppEnvironment": "prod",
            "ApiBaseHostProd": "api.example.com",
            "ApiBaseHostNonProd": "api.nonprod.example.com",
        ])

        #expect(values.defaultEnvironment == .prod)
        #expect(values.configs[.prod] == prod)
        #expect(values.configs[.nonProd] == nonProd)
    }
    // <<< option:buildtime-infoplist
}
