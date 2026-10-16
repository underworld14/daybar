import Foundation

/// One cell of a month calendar.
public struct MonthGridDay: Equatable, Sendable, Identifiable {
    public let date: Date
    public let dayNumber: Int
    public let isInMonth: Bool
    public let isToday: Bool
    public let isPast: Bool

    public var id: Date { date }
}

/// A six-week month layout that follows the calendar's first weekday.
public enum MonthGrid {
    public static let cellCount = 42

    /// Start of the month containing `date`.
    public static func monthStart(_ date: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: parts) ?? DayMath.startOfDay(date, calendar: calendar)
    }

    public static func shift(_ month: Date, by months: Int, calendar: Calendar = .current) -> Date {
        monthStart(calendar.date(byAdding: .month, value: months, to: monthStart(month, calendar: calendar)) ?? month,
                   calendar: calendar)
    }

    /// 42 days starting on the first weekday on or before the 1st of `month`.
    public static func days(for month: Date, today: Date, calendar: Calendar = .current) -> [MonthGridDay] {
        let first = monthStart(month, calendar: calendar)
        let todayStart = DayMath.startOfDay(today, calendar: calendar)
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -lead, to: first) ?? first
        let monthNumber = calendar.component(.month, from: first)
        return (0..<cellCount).compactMap { offset in
            guard let raw = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let date = DayMath.startOfDay(raw, calendar: calendar)
            return MonthGridDay(
                date: date,
                dayNumber: calendar.component(.day, from: date),
                isInMonth: calendar.component(.month, from: date) == monthNumber,
                isToday: date == todayStart,
                isPast: date < todayStart
            )
        }
    }

    /// Very short weekday symbols in display order (starting at `firstWeekday`).
    public static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }
}
