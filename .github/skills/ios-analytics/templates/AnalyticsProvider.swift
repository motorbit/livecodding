import Logging

/// One analytics backend. Vendor SDK code lives only in `AnalyticsProvider+<Vendor>.swift` in this
/// module, so no feature ever imports a vendor SDK.
public struct AnalyticsProvider: Sendable {
    public var track: @Sendable (_ name: String, _ parameters: [String: AnalyticsValue]) -> Void
    public var setUserID: @Sendable (_ id: String?) -> Void
    public var reset: @Sendable () -> Void

    public init(
        track: @escaping @Sendable (_ name: String, _ parameters: [String: AnalyticsValue]) -> Void,
        setUserID: @escaping @Sendable (_ id: String?) -> Void = { _ in },
        reset: @escaping @Sendable () -> Void = {}
    ) {
        self.track = track
        self.setUserID = setUserID
        self.reset = reset
    }
}

// >>> option:log-provider
public extension AnalyticsProvider {
    /// Writes events to the unified log at debug level (dropped in release by the Logging module).
    /// Useful in development and as the only provider until a vendor is chosen.
    static func log(_ logger: LoggingClient) -> Self {
        AnalyticsProvider(
            track: { name, parameters in
                logger.debug("analytics.track", ["event": name, "parameters": String(describing: parameters)])
            },
            setUserID: { id in logger.debug("analytics.setUserID", ["set": String(id != nil)]) },
            reset: { logger.debug("analytics.reset") }
        )
    }
}
// <<< option:log-provider
