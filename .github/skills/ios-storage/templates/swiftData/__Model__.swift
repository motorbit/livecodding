import Foundation
import SwiftData

/// The value type consumers see. `Sendable`, so it can cross actors.
public struct __Model__: Equatable, Identifiable, Sendable {
    public var id: String
    // >>> fields
    public var title: String
    // <<< fields

    public init(
        id: String,
        // >>> fields
        title: String
        // <<< fields
    ) {
        self.id = id
        // >>> fields
        self.title = title
        // <<< fields
    }
}

/// The persisted SwiftData entity. Internal: it's only touched inside `StorageModelActor`.
@Model
final class __Model__Entity {
    @Attribute(.unique) var id: String
    // >>> fields
    var title: String
    // <<< fields

    init(_ value: __Model__) {
        id = value.id
        // >>> fields
        title = value.title
        // <<< fields
    }

    func update(from value: __Model__) {
        // >>> fields
        title = value.title
        // <<< fields
    }

    var value: __Model__ {
        __Model__(
            id: id,
            // >>> fields
            title: title
            // <<< fields
        )
    }
}
