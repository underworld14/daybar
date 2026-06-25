import Foundation

/// Calendar day arithmetic, normalized to start-of-day so day comparisons are
/// DST- and timezone-safe. All callers inject the dates; nothing here reads `Date.now`
/// implicitly except via an explicit default argument.
public enum DayMath {
    /// Midnight at the start of `date` in the given calendar's timezone.
    public static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Whole-day difference between two instants, measured between their start-of-day
    /// values. Crossing a DST boundary still yields the correct integer day count.
    public static func dayDifference(from start: Date, to end: Date, calendar: Calendar = .current) -> Int {
        let s = calendar.startOfDay(for: start)
        let e = calendar.startOfDay(for: end)
        return calendar.dateComponents([.day], from: s, to: e).day ?? 0
    }

    /// Start of the day after `date`.
    public static func nextDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: startOfDay(date, calendar: calendar)) ?? date
    }

    /// True when both instants fall on the same calendar day.
    public static func isSameDay(_ a: Date, _ b: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }
}
