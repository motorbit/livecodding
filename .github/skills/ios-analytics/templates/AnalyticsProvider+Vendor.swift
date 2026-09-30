// import VendorSDK   // add the vendor package to Package.swift, for this target only

public extension AnalyticsProvider {
    /// Adapter for a vendor SDK: map `AnalyticsValue` to the SDK's types here and nowhere else.
    ///
    /// - SDK initialization (API key) happens lazily inside this adapter, or in a route-entry
    ///   effect of the coordinator. Never in the app shell.
    /// - If the SDK requires the main thread, hop inside the closure:
    ///   `Task { @MainActor in VendorSDK.track(name, attributes) }`.
    static func vendor() -> Self {
        AnalyticsProvider(
            track: { name, parameters in
                let attributes = parameters.mapValues(\.vendorValue)
                _ = (name, attributes) // VendorSDK.track(name, attributes)
            },
            setUserID: { id in
                _ = id // VendorSDK.setUserID(id)
            },
            reset: {
                // VendorSDK.reset()
            }
        )
    }
}

private extension AnalyticsValue {
    var vendorValue: any Sendable {
        switch self {
        case .string(let value): value
        case .int(let value): value
        case .double(let value): value
        case .bool(let value): value
        }
    }
}
