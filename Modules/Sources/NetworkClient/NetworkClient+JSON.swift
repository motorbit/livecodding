import Foundation

public extension NetworkClient {
    /// Sends `request`, requires a 2xx status and decodes the JSON body.
    ///
    /// `@concurrent`: the whole exchange (middlewares, status check, decoding) runs off the caller's
    /// actor, and the caller resumes on its own actor with the result.
    @concurrent
    func decode<Response: Decodable & Sendable>(
        _ type: Response.Type = Response.self,
        for request: URLRequest,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws(NetworkError) -> Response {
        let data = try await sendChecked(request)
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw NetworkError(error)
        }
    }

    /// Sends `request`, requires a 2xx status and returns the raw body (e.g. for 204 or non-JSON).
    /// `@concurrent`, like `decode`.
    @concurrent
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
}
