import Foundation
import Testing
@testable import TaskClient

struct DueDayTests {
    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    @Test("""
        Given a local time late in the evening west of UTC,
        When its due day is taken,
        Then it is the local calendar day at 00:00 UTC, not the UTC day
        """)
    func dayUsesLocalCalendarDay() throws {
        // 2025-03-10 23:30 in Los Angeles is 2025-03-11 06:30 UTC.
        let date = try Date("2025-03-11T06:30:00Z", strategy: .iso8601)

        let day = DueDay.day(containing: date, in: calendar("America/Los_Angeles"))

        #expect(day == (try DueDateFormat.date(from: "2025-03-10")))
    }

    @Test("""
        Given a local time early in the morning east of UTC,
        When its due day is taken,
        Then it is the local calendar day
        """)
    func dayEastOfUTC() throws {
        // 2025-03-11 00:30 in Tokyo is 2025-03-10 15:30 UTC.
        let date = try Date("2025-03-10T15:30:00Z", strategy: .iso8601)

        let day = DueDay.day(containing: date, in: calendar("Asia/Tokyo"))

        #expect(day == (try DueDateFormat.date(from: "2025-03-11")))
    }

    @Test("""
        Given two due days,
        When the difference is taken,
        Then whole days are counted in either direction
        """)
    func daysBetween() throws {
        let start = try DueDateFormat.date(from: "2025-02-27")
        let end = try DueDateFormat.date(from: "2025-03-02")

        #expect(DueDay.days(from: start, to: end) == 3)
        #expect(DueDay.days(from: end, to: start) == -3)
        #expect(DueDay.days(from: start, to: start) == 0)
    }

    @Test("""
        Given a UTC date with a time component,
        When it is normalized,
        Then it snaps to 00:00 UTC of the same day
        """)
    func normalizedSnapsToUTCMidnight() throws {
        let date = try Date("2025-03-10T18:45:00Z", strategy: .iso8601)

        #expect(DueDay.normalized(date) == (try DueDateFormat.date(from: "2025-03-10")))
    }
}
