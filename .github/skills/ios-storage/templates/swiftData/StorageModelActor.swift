import Foundation
import SwiftData

/// Owns the `ModelContext` (not `Sendable`) and serializes access to it. Methods map between
/// `@Model` entities and `Sendable` values; entities never cross the actor boundary.
@ModelActor
actor StorageModelActor {
    func fetch__Models__() throws -> [__Model__] {
        let descriptor = FetchDescriptor<__Model__Entity>(sortBy: [SortDescriptor(\.id)])
        return try modelContext.fetch(descriptor).map(\.value)
    }

    func save__Model__(_ value: __Model__) throws {
        if let existing = try find__Model__(value.id) {
            existing.update(from: value)
        } else {
            modelContext.insert(__Model__Entity(value))
        }
        try modelContext.save()
    }

    func delete__Model__(_ id: __Model__.ID) throws {
        guard let existing = try find__Model__(id) else { return }
        modelContext.delete(existing)
        try modelContext.save()
    }

    func deleteAll() throws {
        try modelContext.delete(model: __Model__Entity.self)
        try modelContext.save()
    }

    private func find__Model__(_ id: __Model__.ID) throws -> __Model__Entity? {
        var descriptor = FetchDescriptor<__Model__Entity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
