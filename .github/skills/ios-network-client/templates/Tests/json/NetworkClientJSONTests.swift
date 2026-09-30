import Foundation
import Testing
@testable import NetworkClient

struct NetworkClientJSONTests {
    private struct Item: Decodable, Equatable, Sendable {
        let id: Int
    }

    private let request = URLRequest(url: URL(string: "https://api.example.com/items")!)

    @Test("""
        Given a 200 response with valid JSON,
        When decode is called,
        Then it returns the decoded value
        """)
    func decodeSuccess() async throws {
        let sut = NetworkClient { request in (Data(#"{"id":1}"#.utf8), .stub(request, status: 200)) }

        let item = try await sut.decode(Item.self, for: request)

        #expect(item == Item(id: 1))
    }

    @Test("""
        Given a 404 response,
        When decode is called,
        Then it throws httpStatus(404)
        """)
    func decodeHTTPError() async {
        let sut = NetworkClient { request in (Data(), .stub(request, status: 404)) }

        await #expect(throws: NetworkError.httpStatus(404)) {
            try await sut.decode(Item.self, for: request)
        }
    }

    @Test("""
        Given a body with a wrong type,
        When decode is called,
        Then it throws decoding with the coding path
        """)
    func decodeMismatch() async {
        let sut = NetworkClient { request in (Data(#"{"id":"x"}"#.utf8), .stub(request, status: 200)) }

        await #expect(throws: NetworkError.decoding(path: ".id")) {
            try await sut.decode(Item.self, for: request)
        }
    }

    @Test("""
        Given the transport is offline,
        When decode is called,
        Then it throws transport(notConnectedToInternet)
        """)
    func decodeTransportError() async {
        let sut = NetworkClient { _ in throw URLError(.notConnectedToInternet) }

        await #expect(throws: NetworkError.transport(.notConnectedToInternet)) {
            try await sut.decode(Item.self, for: request)
        }
    }
}
