import AppEnvironment
import Dependencies
import Foundation
import Logging
import NetworkClient
import Testing
@testable import TaskClient

struct TaskNetworkClientHTTPTests {
    private let baseURL = URL(string: "http://localhost:8080")!
    private let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @Test("""
        Given the HTTP client,
        When each Task API call is made,
        Then it sends the matching method, path, JSON body and the create's idempotency key
        """)
    func buildsRequests() async throws {
        let requests = LockIsolated<[URLRequest]>([])
        let dto = TaskDTO(id: id, title: "T", notes: "", priority: .high, done: true, dueDate: "2026-10-01")
        let body = try JSONEncoder().encode(dto)
        try await withDependencies {
            $0.networkClient.send = { request in
                requests.withValue { $0.append(request) }
                switch request.httpMethod {
                case "GET": return (Data("[\(String(decoding: body, as: UTF8.self))]".utf8), .stub(200))
                case "DELETE": return (Data(), .stub(204))
                default: return (body, .stub(request.httpMethod == "POST" ? 201 : 200))
                }
            }
        } operation: {
            let sut = TaskNetworkClient.http(baseURL: baseURL)

            #expect(try await sut.fetchTasks() == [dto])
            #expect(try await sut.createTask(TaskDraftDTO(title: "T", notes: "", priority: .high, dueDate: nil), id) == dto)
            #expect(try await sut.updateTask(dto, nil) == dto)
            try await sut.deleteTask(id, nil)
        }

        let sent = requests.value.map { "\($0.httpMethod ?? "") \($0.url?.absoluteString ?? "")" }
        #expect(sent == [
            "GET http://localhost:8080/tasks",
            "POST http://localhost:8080/tasks",
            "PUT http://localhost:8080/tasks/\(id.uuidString)",
            "DELETE http://localhost:8080/tasks/\(id.uuidString)",
        ])
        let create = try JSONSerialization.jsonObject(with: requests.value[1].httpBody ?? Data()) as? [String: Any]
        #expect(create?["title"] as? String == "T")
        #expect(create?["priority"] as? String == "High")
        #expect(requests.value[1].value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(requests.value[1].value(forHTTPHeaderField: "Idempotency-Key") == id.uuidString)
        let update = try JSONDecoder().decode(TaskDTO.self, from: requests.value[2].httpBody ?? Data())
        #expect(update == dto)
        #expect(requests.value.allSatisfy { $0.value(forHTTPHeaderField: "If-Match") == nil })
    }

    @Test("""
        Given an update and a delete of an expected version,
        When the HTTP client sends them and the server answers 412,
        Then If-Match carries the quoted version and conflict is thrown
        """)
    func sendsIfMatchAndMapsConflict() async {
        let requests = LockIsolated<[URLRequest]>([])
        let dto = TaskDTO(id: id, title: "T", notes: "", priority: .high, done: false, dueDate: nil)
        await withDependencies {
            $0.networkClient.send = { request in
                requests.withValue { $0.append(request) }
                return (Data(#"{"error":"version mismatch"}"#.utf8), .stub(412))
            }
        } operation: {
            let sut = TaskNetworkClient.http(baseURL: baseURL)
            await #expect(throws: TaskNetworkError.conflict) { try await sut.updateTask(dto, 3) }
            await #expect(throws: TaskNetworkError.conflict) { try await sut.deleteTask(id, 3) }
        }
        #expect(requests.value.map { $0.value(forHTTPHeaderField: "If-Match") } == [#""3""#, #""3""#])
    }

    @Test("""
        Given each HTTP or transport failure,
        When the HTTP client fetches tasks,
        Then it throws the matching TaskNetworkError
        """,
        arguments: [
            (400, TaskNetworkError.badRequest),
            (404, .notFound),
            (500, .serverError),
            (503, .serverError),
        ])
    func mapsStatusCodes(status: Int, expected: TaskNetworkError) async {
        await withDependencies {
            $0.networkClient.send = { _ in (Data(#"{"error":"x"}"#.utf8), .stub(status)) }
        } operation: {
            await #expect(throws: expected) {
                try await TaskNetworkClient.http(baseURL: baseURL).fetchTasks()
            }
        }
    }

    @Test("""
        Given the server is unreachable or returns an unexpected body,
        When the HTTP client fetches tasks,
        Then it throws transport
        """)
    func mapsTransportAndDecodingFailures() async {
        await withDependencies {
            $0.networkClient.send = { _ in throw URLError(.cannotConnectToHost) }
        } operation: {
            await #expect(throws: TaskNetworkError.transport) {
                try await TaskNetworkClient.http(baseURL: baseURL).fetchTasks()
            }
        }
        await withDependencies {
            $0.networkClient.send = { _ in (Data("{}".utf8), .stub(200)) }
        } operation: {
            await #expect(throws: TaskNetworkError.transport) {
                try await TaskNetworkClient.http(baseURL: baseURL).fetchTasks()
            }
        }
    }

    @Test("""
        Given the request is cancelled,
        When the HTTP client fetches tasks,
        Then CancellationError propagates
        """)
    func cancellationPropagates() async {
        await withDependencies {
            $0.networkClient.send = { _ in throw URLError(.cancelled) }
        } operation: {
            await #expect(throws: CancellationError.self) {
                try await TaskNetworkClient.http(baseURL: baseURL).fetchTasks()
            }
        }
    }
}

struct TaskNetworkClientEnvironmentTests {
    @Test("""
        Given the active environment changes between calls,
        When tasks are fetched,
        Then each call uses that environment's backend
        """)
    func resolvesBackendPerCall() async throws {
        let backend = LockIsolated(APIBackend.mock)
        let sentURLs = LockIsolated<[String]>([])
        try await withDependencies {
            $0.environmentClient.current = { EnvironmentConfig(environment: .dev, apiBackend: backend.value) }
            $0.networkClient.send = { request in
                sentURLs.withValue { $0.append(request.url?.absoluteString ?? "") }
                return (Data("[]".utf8), .stub(200))
            }
        } operation: {
            let sut = TaskNetworkClient.environmentBacked(mock: .mock(policy: .instant))

            let mocked = try await sut.fetchTasks()
            backend.setValue(.remote(URL(string: "http://localhost:8080")!))
            let remote = try await sut.fetchTasks()

            #expect(mocked.count == 4)
            #expect(remote.isEmpty)
        }
        #expect(sentURLs.value == ["http://localhost:8080/tasks"])
    }

    @Test("""
        Given the mock backend,
        When a task is created and tasks are fetched again,
        Then the shared mock keeps the created task
        """)
    func mockStateIsShared() async throws {
        try await withDependencies {
            $0.environmentClient.current = { EnvironmentConfig(environment: .local, apiBackend: .mock) }
        } operation: {
            let sut = TaskNetworkClient.environmentBacked(mock: .mock(policy: .instant))

            let created = try await sut.createTask(TaskDraftDTO(title: "New", notes: "", priority: .low, dueDate: nil), UUID())

            #expect(try await sut.fetchTasks().last == created)
        }
    }

    @Test("""
        Given an environment without an API base URL,
        When tasks are fetched,
        Then it throws apiBaseURLMissing and logs the error
        """)
    func notConfiguredThrowsAndLogs() async {
        let logged = LockIsolated<[String]>([])
        await withDependencies {
            $0.environmentClient.current = { EnvironmentConfig(environment: .prod, apiBackend: .notConfigured) }
            $0.logger.logError = { _, metadata in logged.withValue { $0.append(metadata["environment"] ?? "") } }
        } operation: {
            await #expect(throws: EnvironmentError.apiBaseURLMissing(.prod)) {
                try await TaskNetworkClient.environmentBacked(mock: .mock(policy: .instant)).fetchTasks()
            }
        }
        #expect(logged.value == ["prod"])
    }
}

private extension HTTPURLResponse {
    static func stub(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "http://localhost")!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}
