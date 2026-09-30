import Analytics

/// Per-feature analytics events. They live in the feature module (e.g. `__Feature__Event.swift`).
/// Adding a case forces an update of both switches, so names and parameters can't drift apart.
enum __Feature__Event: TrackingEvent {
    case screenViewed
    case itemSelected(position: Int)
    case loadFailed(category: String)

    var name: String {
        switch self {
        case .screenViewed: "__feature_snake___screen_viewed"
        case .itemSelected: "__feature_snake___item_selected"
        case .loadFailed: "__feature_snake___load_failed"
        }
    }

    var parameters: [String: AnalyticsValue] {
        switch self {
        case .screenViewed: [:]
        case .itemSelected(let position): ["position": .int(position)]
        case .loadFailed(let category): ["error_category": .string(category)]
        }
    }
}

// In the ViewModel:
//     @Dependency(\.analytics) private var analytics
//     analytics.track(__Feature__Event.itemSelected(position: index))
//
// In tests:
//     let tracked = LockIsolated<[String]>([])
//     $0.analytics.track = { event in tracked.withValue { $0.append(event.name) } }
//     #expect(tracked.value == ["__feature_snake___item_selected"])
