import Dependencies
import Foundation
import NetworkClient

/// `TaskNetworkClient` over HTTP: the Go backend in `backend/` (see `backend/openapi.yaml`).
/// The exchange and decoding run off the caller's actor (`NetworkClient.send` is `@concurrent`).
extension TaskNetworkClient {
    static func http(baseURL: URL) -> Self {
        Self(
            fetchTasks: {
                try await perform(baseURL: baseURL) { Endpoint<[TaskDTO]>(path: "tasks") }
            },
            createTask: { body, idempotencyKey in
                try await perform(baseURL: baseURL) {
                    var endpoint = try Endpoint<TaskDTO>.json(.post, path: "tasks", body: body)
                    endpoint.headers["Idempotency-Key"] = idempotencyKey.uuidString
                    return endpoint
                }
            },
            updateTask: { body, ifMatch in
                try await perform(baseURL: baseURL) {
                    var endpoint = try Endpoint<TaskDTO>.json(.put, path: "tasks/\(body.id.uuidString)", body: body)
                    endpoint.setIfMatch(ifMatch)
                    return endpoint
                }
            },
            deleteTask: { id, ifMatch in
                _ = try await perform(baseURL: baseURL) {
                    var endpoint = Endpoint<EmptyResponse>(method: .delete, path: "tasks/\(id.uuidString)")
                    endpoint.setIfMatch(ifMatch)
                    return endpoint
                }
            }
        )
    }

    /// Sends the endpoint through `\.networkClient` and maps `NetworkError` to the Task API's
    /// errors. Cancellation stays a `CancellationError`, so view models ignore it.
    private static func perform<Response: Decodable & Sendable>(
        baseURL: URL,
        _ makeEndpoint: () throws -> Endpoint<Response>
    ) async throws -> Response {
        @Dependency(\.networkClient) var network
        do {
            return try await network.send(makeEndpoint(), baseURL: baseURL)
        } catch {
            throw TaskNetworkError.map(NetworkError(error))
        }
    }
}

private extension Endpoint {
    mutating func setIfMatch(_ version: Int?) {
        guard let version else { return }
        headers["If-Match"] = "\"\(version)\""
    }
}

extension TaskNetworkError {
    static func map(_ error: NetworkError) -> any Error {
        switch error {
        case .httpStatus(400): TaskNetworkError.badRequest
        case .httpStatus(404): TaskNetworkError.notFound
        case .httpStatus(412): TaskNetworkError.conflict
        case .httpStatus: TaskNetworkError.serverError
        case .cancelled: CancellationError()
        case .transport, .decoding, .invalidRequest, .unknown: TaskNetworkError.transport
        }
    }
}
