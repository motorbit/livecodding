import Dependencies
import DependenciesMacros
import Foundation
import Network

/// Whether the device has a usable network path (Wi-Fi, cellular, …), from `NWPathMonitor`. It
/// doesn't prove a server is reachable; it only says when trying again is worthwhile.
@DependencyClient
public struct NetworkMonitorClient: Sendable {
    /// The current value first, then every change. Each call starts its own monitor, which stops
    /// when the stream is no longer iterated.
    public var isOnlineUpdates: @Sendable () -> AsyncStream<Bool> = { AsyncStream { $0.finish() } }
}

extension NetworkMonitorClient: DependencyKey {
    public static let liveValue = NetworkMonitorClient(
        isOnlineUpdates: {
            AsyncStream { continuation in
                let monitor = NWPathMonitor()
                monitor.pathUpdateHandler = { path in
                    continuation.yield(path.status == .satisfied)
                }
                continuation.onTermination = { _ in monitor.cancel() }
                monitor.start(queue: DispatchQueue(label: "NetworkMonitorClient"))
            }
        }
    )

    public static let previewValue = NetworkMonitorClient(
        isOnlineUpdates: { AsyncStream { $0.yield(true) } }
    )

    public static let testValue = NetworkMonitorClient()
}

public extension DependencyValues {
    var networkMonitorClient: NetworkMonitorClient {
        get { self[NetworkMonitorClient.self] }
        set { self[NetworkMonitorClient.self] = newValue }
    }
}
