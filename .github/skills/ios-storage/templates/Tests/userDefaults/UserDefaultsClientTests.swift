import Foundation
import Testing
@testable import __Module__

struct UserDefaultsClientTests {
    private struct Filter: Codable, Equatable {
        var query: String
        var limit: Int
    }

    private let flag = UserDefaultsKey<Bool>("flag", default: false)
    private let count = UserDefaultsKey<Int>("count", default: 0)
    private let name = UserDefaultsKey<String>("name", default: "")
    private let filter = UserDefaultsKey<Filter>.codable("filter", default: Filter(query: "", limit: 10))

    @Test("""
        Given an in-memory client,
        When primitive and Codable values are set,
        Then they read back with their types
        """)
    func inMemoryRoundTrip() throws {
        let sut = UserDefaultsClient.inMemory()

        try sut.set(true, for: flag)
        try sut.set(3, for: count)
        try sut.set(Filter(query: "milk", limit: 5), for: filter)

        #expect(sut.value(flag) == true)
        #expect(sut.value(count) == 3)
        #expect(sut.value(filter) == Filter(query: "milk", limit: 5))
    }

    @Test("""
        Given a stored value,
        When it's removed,
        Then the key's default is returned
        """)
    func removeReturnsDefault() throws {
        let sut = UserDefaultsClient.inMemory()
        try sut.set("Ann", for: name)

        sut.remove(name)

        #expect(sut.value(name) == "")
    }

    @Test("""
        Given a value of another kind under the same name,
        When it's read with a typed key,
        Then the key's default is returned
        """)
    func kindMismatchReturnsDefault() {
        let sut = UserDefaultsClient.inMemory(["count": .string("three")])

        #expect(sut.value(count) == 0)
    }

    @Test("""
        Given stored data that no longer decodes,
        When it's read with a Codable key,
        Then the key's default is returned
        """)
    func undecodableCodableReturnsDefault() {
        let sut = UserDefaultsClient.inMemory(["filter": .data(Data("{}".utf8))])

        #expect(sut.value(filter) == Filter(query: "", limit: 10))
    }

    @Test("""
        Given the live client over a throwaway suite,
        When every primitive kind is written and read,
        Then UserDefaults stores them natively and they round-trip
        """)
    func liveRoundTrip() throws {
        let suiteName = "UserDefaultsClientTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sut = UserDefaultsClient.live(defaults)
        let date = Date(timeIntervalSince1970: 1_000)

        try sut.set(true, for: flag)
        try sut.set(7, for: count)
        try sut.set("Ann", for: name)
        try sut.set(2.5, for: UserDefaultsKey<Double>("ratio", default: 0))
        try sut.set(Data([1, 2]), for: UserDefaultsKey<Data>("blob", default: Data()))
        try sut.set(date, for: UserDefaultsKey<Date>("date", default: .distantPast))
        try sut.set(Filter(query: "tea", limit: 1), for: filter)

        #expect(defaults.bool(forKey: "flag"))
        #expect(defaults.integer(forKey: "count") == 7)
        #expect(sut.value(flag) == true)
        #expect(sut.value(count) == 7)
        #expect(sut.value(name) == "Ann")
        #expect(sut.value(UserDefaultsKey<Double>("ratio", default: 0)) == 2.5)
        #expect(sut.value(UserDefaultsKey<Data>("blob", default: Data())) == Data([1, 2]))
        #expect(sut.value(UserDefaultsKey<Date>("date", default: .distantPast)) == date)
        #expect(sut.value(filter) == Filter(query: "tea", limit: 1))

        sut.remove(count)
        #expect(defaults.object(forKey: "count") == nil)
    }
}
