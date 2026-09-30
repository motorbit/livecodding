import Dependencies
import DependenciesMacros
import Foundation

/// A small local database on SwiftData. The client owns one `ModelContainer`; all `ModelContext`
/// work runs inside `StorageModelActor` (a `@ModelActor`), so `@Model` objects never leave it.
/// Endpoints take and return `Sendable` value types (`__Model__`), never `@Model` objects.
///
/// One endpoint group per model type. Add a group (and a `__Model__.swift` file) per type.
@DependencyClient
public struct SwiftDataClient: Sendable {
    /// Sorted by `id`.
    public var fetch__Models__: @Sendable () async throws -> [__Model__]
    /// Inserts, or updates the stored item with the same `id`.
    public var save__Model__: @Sendable (_ value: __Model__) async throws -> Void
    /// No-op if there's no item with `id`.
    public var delete__Model__: @Sendable (_ id: __Model__.ID) async throws -> Void
    /// Removes every stored item of every model type (e.g. on sign-out).
    public var deleteAll: @Sendable () async throws -> Void
}

extension SwiftDataClient: DependencyKey {
    // >>> config
    public static let liveValue = SwiftDataClient.live(.onDisk)
    // or, to share the store with app extensions: .live(.appGroup("__AppGroup__"))
    // <<< config

    /// Unimplemented. Tests that exercise storage use `.inMemory()`.
    public static let testValue = SwiftDataClient()

    /// Previews get an empty, throwaway store.
    public static let previewValue = SwiftDataClient.inMemory()
}

public extension DependencyValues {
    var swiftDataClient: SwiftDataClient {
        get { self[SwiftDataClient.self] }
        set { self[SwiftDataClient.self] = newValue }
    }
}

public extension SwiftDataClient {
    /// The real SwiftData stack over an in-memory store
    /// (`ModelConfiguration(isStoredInMemoryOnly: true)`). Each call gets its own empty store.
    static func inMemory() -> Self {
        live(.inMemory)
    }
}
