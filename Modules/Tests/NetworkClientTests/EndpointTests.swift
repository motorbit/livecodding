import Foundation
import Testing
@testable import NetworkClient

struct EndpointTests {
    private let baseURL = URL(string: "https://api.example.com")!

    @Test("""
        Given an endpoint with path, query and headers,
        When the request is built,
        Then URL, method and headers match
        """)
    func makeRequest() throws {
        let endpoint = Endpoint<EmptyResponse>(
            method: .delete,
            path: "v1/items/7",
            query: [URLQueryItem(name: "force", value: "true")],
            headers: ["X-Feature": "a"]
        )

        let request = try endpoint.makeRequest(baseURL: baseURL)

        #expect(request.url?.absoluteString == "https://api.example.com/v1/items/7?force=true")
        #expect(request.httpMethod == "DELETE")
        #expect(request.value(forHTTPHeaderField: "X-Feature") == "a")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("""
        Given a JSON body endpoint,
        When the request is built,
        Then the body is encoded and Content-Type is set
        """)
    func jsonBody() throws {
        struct Body: Encodable { let name: String }
        let endpoint = try Endpoint<EmptyResponse>.json(.post, path: "v1/items", body: Body(name: "x"))

        let request = try endpoint.makeRequest(baseURL: baseURL)

        #expect(request.httpBody == Data(#"{"name":"x"}"#.utf8))
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("""
        Given an EmptyResponse endpoint and a 204,
        When it is sent,
        Then it succeeds without decoding
        """)
    func emptyResponse() async throws {
        let sut = NetworkClient { request in (Data(), .stub(request, status: 204)) }

        let response = try await sut.send(Endpoint<EmptyResponse>(method: .delete, path: "v1/items/7"), baseURL: baseURL)

        #expect(response == EmptyResponse())
    }
}
