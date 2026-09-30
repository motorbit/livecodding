import Foundation
import Synchronization

extension __Name__Client {
    /// Builds the live client. Shared state lives in one `Sendable` object that the closures
    /// capture. `live(storage:)` is internal so tests can inject a sandboxed storage.
    static func live(storage: Live__Name__Storage = Live__Name__Storage()) -> Self {
        Self(
            load: { try await storage.load() },
            cachedValue: { storage.cachedValue() },
            clear: { await storage.clear() }
        )
    }
}

/// Example live backing: file I/O with an in-memory cache. Replace it with the real system API.
///
/// - Sync state uses `Mutex` (Synchronization, iOS 18+), so `cachedValue()` can stay synchronous.
/// - Blocking work is `@concurrent`, so it runs on the global executor even when the caller is on
///   MainActor. Without that, `NonisolatedNonsendingByDefault` would run it on the caller's actor.
final class Live__Name__Storage: Sendable {
    private let fileURL: URL
    private let cache = Mutex<String?>(nil)

    init(fileURL: URL = URL.cachesDirectory.appending(path: "__name__.txt")) {
        self.fileURL = fileURL
    }

    func cachedValue() -> String? {
        cache.withLock { $0 }
    }

    @concurrent
    func load() async throws -> String {
        let value = try String(contentsOf: fileURL, encoding: .utf8)
        cache.withLock { $0 = value }
        return value
    }

    @concurrent
    func clear() async {
        cache.withLock { $0 = nil }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
