import Dependencies
import DependenciesMacros

/// __Name__Client: <one line: what capability this client provides>.
///
/// - Structs of `@Sendable` closures, not protocols (ADR 0004).
/// - This module is a client module with nonisolated default isolation. The struct is `Sendable`,
///   so it stays nonisolated even if it's ever compiled with MainActor default isolation (SE-0466).
/// - Under `NonisolatedNonsendingByDefault`, async endpoints run on the **caller's** actor
///   (usually MainActor). The live implementation must move blocking or CPU-heavy work off it with
///   `@concurrent` (see `Live__Name__Client.swift`).
@DependencyClient
public struct __Name__Client: Sendable {
    /// Async, throwing: no default needed. Unimplemented calls throw and report a test failure.
    public var load: @Sendable () async throws -> String

    /// Sync and non-Void: the macro requires a default return value.
    public var cachedValue: @Sendable () -> String? = { nil }

    /// Void: no default needed.
    public var clear: @Sendable () async -> Void
}

extension __Name__Client: DependencyKey {
    public static let liveValue: __Name__Client = .live()

    /// Canned data for SwiftUI previews. Keep it deterministic and fast; never hit the real system.
    public static let previewValue = __Name__Client(
        load: { "Preview value" },
        cachedValue: { "Preview value" },
        clear: {}
    )

    /// ALWAYS unimplemented (`Self()`), never a no-op. If it were omitted, `withDependencies`
    /// overrides would be applied on top of `previewValue`/`liveValue`, so endpoints that a test
    /// didn't stub would silently run real code.
    public static let testValue = __Name__Client()
}

public extension DependencyValues {
    var __name__Client: __Name__Client {
        get { self[__Name__Client.self] }
        set { self[__Name__Client.self] = newValue }
    }
}
