import Dependencies
import Foundation
import Testing
@testable import NetworkClient

struct NetworkMiddlewareCompositionTests {
    @Test("""
        Given two middlewares,
        When they are composed around a transport,
        Then the first one is outermost
        """)
    func firstMiddlewareIsOutermost() async throws {
        let order = LockIsolated<[String]>([])
        func tagging(_ name: String) -> NetworkMiddleware {
            NetworkMiddleware { next in
                { request in
                    order.withValue { $0.append("\(name)>") }
                    let result = try await next(request)
                    order.withValue { $0.append("<\(name)") }
                    return result
                }
            }
        }
        let send = [tagging("outer"), tagging("inner")].compose { request in
            order.withValue { $0.append("transport") }
            return (Data(), HTTPURLResponse.stub(request, status: 200))
        }

        _ = try await send(URLRequest(url: URL(string: "https://example.com")!))

        #expect(order.value == ["outer>", "inner>", "transport", "<inner", "<outer"])
    }
}

extension HTTPURLResponse {
    /// Shared test helper for all network tests in this target.
    static func stub(_ request: URLRequest, status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}
