import Foundation

/// Typed failures of `NetworkClient` JSON calls. The associated values are safe to log: they
/// carry no bodies, tokens or URLs with query values.
public enum NetworkError: Error, Equatable, Sendable {
    /// No usable response (offline, timeout, TLS, …).
    case transport(URLError.Code)
    /// A response outside 200..<300.
    case httpStatus(Int)
    /// The body doesn't match `Response`. `path` is the coding path, e.g. "items[2].id".
    case decoding(path: String)
    /// The request couldn't be built (bad URL, encoding failure).
    case invalidRequest
    case cancelled
    case unknown

    /// Maps any error thrown by `send` or a middleware to `NetworkError`.
    public init(_ error: any Error) {
        switch error {
        case let error as NetworkError:
            self = error
        case is CancellationError:
            self = .cancelled
        case let error as URLError where error.code == .cancelled:
            self = .cancelled
        case let error as URLError:
            self = .transport(error.code)
        case let error as DecodingError:
            self = .decoding(path: error.codingPathDescription)
        default:
            self = .unknown
        }
    }
}

private extension DecodingError {
    var codingPathDescription: String {
        let path: [any CodingKey] = switch self {
        case .typeMismatch(_, let context),
             .valueNotFound(_, let context),
             .keyNotFound(_, let context),
             .dataCorrupted(let context):
            context.codingPath
        @unknown default:
            []
        }
        return path.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
    }
}
