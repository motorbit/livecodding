import Foundation

/// Host-scoped push routes. Carries identifiers only; child view models live in the host VM.
public enum TaskBoardRoute: Hashable, Sendable {
    case detail(id: UUID)
}
