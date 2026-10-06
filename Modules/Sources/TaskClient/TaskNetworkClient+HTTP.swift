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
            updateTask: { body in
                try await perform(baseURL: baseURL) {
                    try .json(.put, path: "tasks/\(body.id.uuidString)", body: body)
                }
            },
            deleteTask: { id in
                _ = try await perform(baseURL: baseURL) {
                    Endpoint<EmptyResponse>(method: .delete, path: "tasks/\(id.uuidString)")
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

extension TaskNetworkError {
    static func map(_ error: NetworkError) -> any Error {
        switch error {
        case .httpStatus(400): TaskNetworkError.badRequest
        case .httpStatus(404): TaskNetworkError.notFound
        case .httpStatus: TaskNetworkError.serverError
        case .cancelled: CancellationError()
        case .transport, .decoding, .invalidRequest, .unknown: TaskNetworkError.transport
        }
    }
}
