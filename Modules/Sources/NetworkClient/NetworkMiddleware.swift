import Foundation

/// Wraps an `HTTPSend` with cross-cutting behaviour (auth, retry, logging, …). Each option of the
/// skill adds one static factory in its own `NetworkMiddleware+<Option>.swift` file.
public struct NetworkMiddleware: Sendable {
    public let wrap: @Sendable (_ next: @escaping HTTPSend) -> HTTPSend

    public init(wrap: @escaping @Sendable (_ next: @escaping HTTPSend) -> HTTPSend) {
        self.wrap = wrap
    }
}

public extension Array where Element == NetworkMiddleware {
    /// Composes middlewares around `transport`. `self[0]` is the OUTERMOST: it sees the request
    /// first and the response last.
    func compose(around transport: @escaping HTTPSend) -> HTTPSend {
        reversed().reduce(transport) { next, middleware in middleware.wrap(next) }
    }
}
