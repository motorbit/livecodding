import Foundation

/// A task's due date is a calendar day stored as 00:00 UTC, independent of the device time zone.
/// Date pickers should display it with `.environment(\.timeZone, DueDay.timeZone)`.
public enum DueDay {
    public static let timeZone: TimeZone = .gmt

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }()

    /// The due day for the local calendar day containing `date` (e.g. "today" from `\.date.now`).
    public static func day(containing date: Date, in calendar: Calendar) -> Date {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let components = gregorian.dateComponents([.year, .month, .day], from: date)
        return utc.date(from: components) ?? normalized(date)
    }

    /// Snaps a date that is already expressed in UTC (e.g. from a UTC date picker) to 00:00 UTC.
    public static func normalized(_ date: Date) -> Date {
        utc.startOfDay(for: date)
    }

    /// Whole days from `start` to `end`; both are due days.
    public static func days(from start: Date, to end: Date) -> Int {
        utc.dateComponents([.day], from: normalized(start), to: normalized(end)).day ?? 0
    }
}
