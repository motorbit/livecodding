import Dependencies
import DependenciesMacros

/// Severity, mapped 1:1 to `os.Logger` levels by the live implementation.
public enum LogLevel: String, Sendable, CaseIterable {
    case debug
    case info
    case notice
    case warning
    case error
    case fault
}

/// The only logging entry point in the app. Never use `print` or `os.Logger` directly.
///
/// - `message` is logged as public: keep it static and free of user data.
/// - `metadata` values are logged as private (redacted in release unless a profile enables them).
@DependencyClient
public struct LoggingClient: Sendable {
    /// Writes `message` at `level` with optional key/value `metadata`.
    public var log: @Sendable (_ level: LogLevel, _ message: String, _ metadata: [String: String]) -> Void

    /// Records an error with context. The error's description is treated as private.
    public var logError: @Sendable (_ error: any Error, _ metadata: [String: String]) -> Void
}

public extension LoggingClient {
    func debug(_ message: String, _ metadata: [String: String] = [:]) { log(.debug, message, metadata) }
    func info(_ message: String, _ metadata: [String: String] = [:]) { log(.info, message, metadata) }
    func notice(_ message: String, _ metadata: [String: String] = [:]) { log(.notice, message, metadata) }
    func warning(_ message: String, _ metadata: [String: String] = [:]) { log(.warning, message, metadata) }
    func error(_ error: any Error, _ metadata: [String: String] = [:]) { logError(error, metadata) }
}

extension LoggingClient: DependencyKey {
    public static let liveValue = LiveLoggingClient.make()

    /// Unimplemented endpoints: a test that logs without overriding `log`/`logError` fails.
    /// Suites stub them once in their `makeDependencies()`.
    public static let testValue = LoggingClient()
}

public extension DependencyValues {
    var logger: LoggingClient {
        get { self[LoggingClient.self] }
        set { self[LoggingClient.self] = newValue }
    }
}
