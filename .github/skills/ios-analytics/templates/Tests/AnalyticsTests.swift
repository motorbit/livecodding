import Dependencies
import Testing
@testable import Analytics

struct AnalyticsTests {
    private enum SampleEvent: TrackingEvent {
        case itemAdded(count: Int)
        case badName

        var name: String {
            switch self {
            case .itemAdded: "item_added"
            case .badName: "Bad Name"
            }
        }

        var parameters: [String: AnalyticsValue] {
            switch self {
            case .itemAdded(let count): ["item_count": .int(count)]
            case .badName: [:]
            }
        }
    }

    @Test("""
        Given two providers,
        When an event is tracked,
        Then both receive its name and parameters
        """)
    func fansOutToProviders() {
        let received = LockIsolated<[String]>([])
        let provider = AnalyticsProvider { name, parameters in
            received.withValue { $0.append("\(name):\(parameters["item_count"] == .int(2))") }
        }
        let sut = AnalyticsClient.live(providers: [provider, provider])

        sut.track(SampleEvent.itemAdded(count: 2))

        #expect(received.value == ["item_added:true", "item_added:true"])
    }

    @Test("""
        Given an event whose name breaks the naming rules,
        When it is tracked,
        Then an issue is reported
        """)
    func invalidNameReportsIssue() {
        let sut = AnalyticsClient.live(providers: [])

        withKnownIssue {
            sut.track(SampleEvent.badName)
        }
    }

    @Test("""
        Given names in various formats,
        When they are validated,
        Then only snake_case ASCII names are valid
        """,
        arguments: [
            ("sign_in_completed", true),
            ("screen_viewed2", true),
            ("SignIn", false),
            ("sign-in", false),
            ("_leading", false),
            ("", false),
        ])
    func nameValidation(name: String, isValid: Bool) {
        #expect(TrackingEventName.isValid(name) == isValid)
    }

    @Test("""
        Given text containing an email, URL, UUID and a long number,
        When it is sanitized,
        Then each is replaced by a placeholder
        """)
    func sanitizerRedacts() {
        let text = "Failed for a.b@example.com at https://x.io/p?q=1 id 123e4567-e89b-12d3-a456-426614174000 n 12345678"

        let result = AnalyticsSanitizer.sanitize(text, maxLength: 500)

        #expect(result == "Failed for <email> at <url> id <uuid> n <number>")
    }
}
