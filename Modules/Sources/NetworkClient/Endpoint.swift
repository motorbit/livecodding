import Foundation

/// A typed description of one API call. API clients build `Endpoint`s; `NetworkClient.send(_:)`
/// turns one into a `URLRequest` and decodes `Response`. Requires the `json` option.
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public var method: HTTPMethod
    /// Relative to the base URL, e.g. "v1/profile". No leading slash is needed.
    public var path: String
    public var query: [URLQueryItem]
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval

    public init(
        method: HTTPMethod = .get,
        path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 30
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }

    /// An endpoint with a JSON-encoded body and the matching `Content-Type`.
    public static func json(
        _ method: HTTPMethod,
        path: String,
        body: some Encodable,
        encoder: JSONEncoder = JSONEncoder()
    ) throws(NetworkError) -> Self {
        guard let data = try? encoder.encode(body) else { throw .invalidRequest }
        return Self(method: method, path: path, headers: ["Content-Type": "application/json"], body: data)
    }

    public func makeRequest(baseURL: URL) throws(NetworkError) -> URLRequest {
        var url = baseURL.appending(path: path)
        if !query.isEmpty {
            url.append(queryItems: query)
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = body
        return request
    }
}

public struct HTTPMethod: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let get = HTTPMethod(rawValue: "GET")
    public static let post = HTTPMethod(rawValue: "POST")
    public static let put = HTTPMethod(rawValue: "PUT")
    public static let patch = HTTPMethod(rawValue: "PATCH")
    public static let delete = HTTPMethod(rawValue: "DELETE")
}

/// `Response` for endpoints without a body (204 and similar).
public struct EmptyResponse: Decodable, Equatable, Sendable {
    public init() {}
}

public extension NetworkClient {
    func send<Response>(
        _ endpoint: Endpoint<Response>,
        baseURL: URL,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws(NetworkError) -> Response {
        let request = try endpoint.makeRequest(baseURL: baseURL)
        if Response.self == EmptyResponse.self {
            _ = try await sendChecked(request)
            return EmptyResponse() as! Response
        }
        return try await decode(Response.self, for: request, decoder: decoder)
    }
}
