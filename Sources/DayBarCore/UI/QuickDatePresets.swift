import Foundation

/// One-click planning targets for the date picker.
public struct QuickDatePreset: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case today, tomorrow, thisWeekend, nextWeek
    }

    public let kind: Kind
    public let title: String
    /// Start of the target day.
    public let date: Date

    public var id: Kind { kind }
}

public enum QuickDatePresets {
    /// Today, Tomorrow, This weekend (the coming Saturday, or today on a weekend), Next week
    /// (the next Monday). A preset that lands on the same day as an earlier one is dropped.
    public static func presets(now: Date, calendar: Calendar = .current) -> [QuickDatePreset] {
        let today = DayMath.startOfDay(now, calendar: calendar)
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday … 7 = Saturday
        let isWeekend = weekday == 1 || weekday == 7
        let weekend = isWeekend ? today : day(today, plus: (7 - weekday + 7) % 7, calendar: calendar)
        let toMonday = (2 - weekday + 7) % 7
        let nextMonday = day(today, plus: toMonday == 0 ? 7 : toMonday, calendar: calendar)

        let candidates = [
            QuickDatePreset(kind: .today, title: "Today", date: today),
            QuickDatePreset(kind: .tomorrow, title: "Tomorrow", date: DayMath.nextDay(today, calendar: calendar)),
            QuickDatePreset(kind: .thisWeekend, title: "This weekend", date: weekend),
            QuickDatePreset(kind: .nextWeek, title: "Next week", date: nextMonday),
        ]
        var seen = Set<Date>()
        return candidates.filter { seen.insert($0.date).inserted }
    }

    private static func day(_ start: Date, plus days: Int, calendar: Calendar) -> Date {
        DayMath.startOfDay(calendar.date(byAdding: .day, value: days, to: start) ?? start, calendar: calendar)
    }
}
