import Foundation
import Testing
@testable import AppEnvironment

struct EnvironmentClientTests {
    private let local = EnvironmentConfig(environment: .local, apiBackend: .mock)
    private let dev = EnvironmentConfig(environment: .dev, apiBackend: .remote(URL(string: "http://localhost:8080")!))
    private let prod = EnvironmentConfig(environment: .prod, apiBackend: .remote(URL(string: "https://api.example.com")!))

    private func build(default environment: AppEnvironment, allowsOverride: Bool) -> BuildValues {
        BuildValues(defaultEnvironment: environment, configs: [.local: local, .dev: dev, .prod: prod], allowsOverride: allowsOverride)
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
        let sut = EnvironmentClient.live(build: build(default: .local, allowsOverride: true), defaults: makeDefaults())

        #expect(sut.current() == local)
    }

    @Test("""
        Given overrides are allowed,
        When an override is set and then cleared,
        Then current follows it and falls back to the default
        """)
    func overrideAllowed() {
        let sut = EnvironmentClient.live(build: build(default: .local, allowsOverride: true), defaults: makeDefaults())

        sut.setOverride(.dev)
        let overridden = sut.current()
        sut.setOverride(nil)

        #expect(overridden == dev)
        #expect(sut.current() == local)
        #expect(sut.selectableEnvironments() == [local, dev, prod])
    }

    @Test("""
        Given a prod release build with a stale override stored by a debug build,
        When current is read,
        Then the override is ignored and removed
        """)
    func overrideIgnoredInProdRelease() {
        let defaults = makeDefaults()
        defaults.set(AppEnvironment.dev.rawValue, forKey: EnvironmentClient.overrideKey)
        let sut = EnvironmentClient.live(build: build(default: .prod, allowsOverride: false), defaults: defaults)

        #expect(sut.current() == prod)
        #expect(defaults.string(forKey: EnvironmentClient.overrideKey) == nil)
        #expect(sut.selectableEnvironments().isEmpty)
    }

    @Test("""
        Given build values for an API base URL,
        When they are parsed,
        Then valid URLs become remote backends and empty or invalid ones are not configured
        """)
    func apiBackendFromBuildValue() {
        #expect(APIBackend.url("http://localhost:8080") == .remote(URL(string: "http://localhost:8080")!))
        #expect(APIBackend.url("https://api.example.com") == .remote(URL(string: "https://api.example.com")!))
        #expect(APIBackend.url("") == .notConfigured)
        #expect(APIBackend.url("localhost") == .notConfigured)
    }
}
