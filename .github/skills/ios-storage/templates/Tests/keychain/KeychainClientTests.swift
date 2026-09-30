import Foundation
import Security
import Testing
@testable import __Module__

/// SPM test bundles run without a host app, so they have no keychain entitlement (SecItem returns
/// -34018). That's why these tests cover the pure query builders and the in-memory client. Verify
/// the live store manually, or from a host-app test target.
struct KeychainClientTests {
    private let configuration = KeychainConfiguration(
        service: "com.example.test",
        accessibility: .afterFirstUnlockThisDeviceOnly,
        accessGroup: "TEAMID.shared"
    )

    @Test("""
        Given a configuration with an access group,
        When an item query is built,
        Then it has class, service, account and access group
        """)
    func itemQuery() {
        let query = KeychainQuery.item("token", configuration)

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == "com.example.test")
        #expect(query[kSecAttrAccount as String] as? String == "token")
        #expect(query[kSecAttrAccessGroup as String] as? String == "TEAMID.shared")
    }

    @Test("""
        Given an accessibility class,
        When write attributes are built,
        Then they carry the matching kSecAttrAccessible value
        """)
    func writeAttributes() {
        let attributes = KeychainQuery.writeAttributes(Data([1]), configuration)

        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(attributes[kSecValueData as String] as? Data == Data([1]))
    }

    @Test("""
        Given an in-memory keychain,
        When a string is set, read, deleted and read again,
        Then it round-trips and is then gone
        """)
    func inMemoryRoundTrip() async throws {
        let sut = KeychainClient.inMemory()

        try await sut.setString("secret", "token")
        let stored = try await sut.string("token")
        try await sut.delete("token")
        let deleted = try await sut.string("token")

        #expect(stored == "secret")
        #expect(deleted == nil)
    }
}
