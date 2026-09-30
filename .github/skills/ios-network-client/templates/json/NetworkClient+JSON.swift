import Foundation

public extension NetworkClient {
    /// Sends `request`, requires a 2xx status and decodes the JSON body **off the main actor**.
    ///
    /// Under `NonisolatedNonsendingByDefault` this method runs on the caller's actor (usually
    /// MainActor). The network wait suspends, but decoding is CPU work, so it's moved to the
    /// `@concurrent` helper below.
    func decode<Response: Decodable & Sendable>(
        _ type: Response.Type = Response.self,
        for request: URLRequest,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws(NetworkError) -> Response {
        let data = try await sendChecked(request)
        return try await Self.decodeOffMain(type, from: data, decoder: decoder)
    }

    /// Sends `request`, requires a 2xx status and returns the raw body (e.g. for 204 or non-JSON).
    func sendChecked(_ request: URLRequest) async throws(NetworkError) -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await send(request)
        } catch {
            throw NetworkError(error)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw .httpStatus(response.statusCode)
        }
        return data
    }

    @concurrent
    private static func decodeOffMain<Response: Decodable & Sendable>(
        _ type: Response.Type,
        from data: Data,
        decoder: JSONDecoder
    ) async throws(NetworkError) -> Response {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw NetworkError(error)
        }
    }
}
