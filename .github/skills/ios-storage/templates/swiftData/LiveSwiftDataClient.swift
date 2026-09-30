import Dependencies
import Foundation
import SwiftData

/// Where the SwiftData store lives. Decide it once per app: moving it later needs a migration.
public enum SwiftDataStoreLocation: Equatable, Sendable {
    /// The app's own container (Application Support).
    case onDisk
    /// A shared app group container, readable by extensions in the same group.
    case appGroup(String)
    /// Ephemeral; for tests and previews.
    case inMemory
}

/// Every `@Model` type the store holds. Add new model types here.
enum StorageSchema {
    static var schema: Schema {
        Schema([
            __Model__Entity.self,
        ])
    }

    static func configuration(_ location: SwiftDataStoreLocation) -> ModelConfiguration {
        switch location {
        case .onDisk:
            // Explicit `.none`: the `.automatic` defaults would pick up an app group or CloudKit
            // entitlement silently.
            ModelConfiguration(schema: schema, groupContainer: .none, cloudKitDatabase: .none)
        case let .appGroup(identifier):
            ModelConfiguration(schema: schema, groupContainer: .identifier(identifier), cloudKitDatabase: .none)
        case .inMemory:
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none)
        }
    }

    static func makeContainer(_ location: SwiftDataStoreLocation) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [configuration(location)])
    }
}

extension SwiftDataClient {
    static func live(_ location: SwiftDataStoreLocation) -> Self {
        let store = LiveSwiftDataStore(location: location)
        return Self(
            fetch__Models__: { try await store.actor().fetch__Models__() },
            save__Model__: { value in try await store.actor().save__Model__(value) },
            delete__Model__: { id in try await store.actor().delete__Model__(id) },
            deleteAll: { try await store.actor().deleteAll() }
        )
    }
}

/// Opens the container lazily on first use, so a failure surfaces as a thrown error from an
/// endpoint instead of a crash while building `liveValue`.
final class LiveSwiftDataStore: Sendable {
    private let location: SwiftDataStoreLocation
    private let cached = LockIsolated<StorageModelActor?>(nil)

    init(location: SwiftDataStoreLocation) {
        self.location = location
    }

    /// Opening the store is blocking file I/O, so it runs off the caller's actor.
    @concurrent
    func actor() async throws -> StorageModelActor {
        try cached.withValue { cached in
            if let cached { return cached }
            let actor = StorageModelActor(modelContainer: try StorageSchema.makeContainer(location))
            cached = actor
            return actor
        }
    }
}
