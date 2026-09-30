import Foundation
import os

/// `os.Logger`-backed implementation. Messages are public; metadata and error descriptions are
/// private, so release builds never leak user data into the unified log.
enum LiveLoggingClient {
    static func make(
        subsystem: String = Bundle.main.bundleIdentifier ?? "app",
        category: String = "app"
    ) -> LoggingClient {
        let logger = Logger(subsystem: subsystem, category: category)
        return LoggingClient(
            log: { level, message, metadata in
                #if !DEBUG
                if level == .debug { return }
                #endif
                let meta = format(metadata)
                logger.log(level: level.osLogType, "\(message, privacy: .public)\(meta, privacy: .private)")
            },
            logError: { error, metadata in
                let meta = format(metadata)
                logger.error("\(String(describing: error), privacy: .private)\(meta, privacy: .private)")
            }
        )
    }

    private static func format(_ metadata: [String: String]) -> String {
        guard !metadata.isEmpty else { return "" }
        let pairs = metadata.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        return " | " + pairs.joined(separator: " ")
    }
}

private extension LogLevel {
    var osLogType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .notice: .default
        case .warning: .error
        case .error: .error
        case .fault: .fault
        }
    }
}
