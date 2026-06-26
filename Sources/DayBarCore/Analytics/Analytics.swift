import Foundation

public enum Granularity: Sendable, CaseIterable {
    case day, week, month
}

/// One aggregated period for the analytics charts.
public struct StatBucket: Sendable, Identifiable {
    public let date: Date   // start of the period
    public var planned: Int
    public var completed: Int
    public var focusMinutes: Int

    public var id: Date { date }
    public var completionRate: Double { planned == 0 ? 0 : Double(completed) / Double(planned) }

    public init(date: Date, planned: Int = 0, completed: Int = 0, focusMinutes: Int = 0) {
        self.date = date
        self.planned = planned
        self.completed = completed
        self.focusMinutes = focusMinutes
    }
}

/// Pure, testable aggregation over todos + focus sessions. Planned/completed are binned by the
/// stable `originalPlannedDate` (the day the task was planned for); focus minutes by
/// `endedAt`. Period keys use `Calendar`, so it is DST/timezone-safe.
public enum Analytics {
    public static func periodStart(_ date: Date, _ g: Granularity, calendar: Calendar = .current) -> Date {
        switch g {
        case .day:   return calendar.startOfDay(for: date)
        case .week:  return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .month: return calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }

    public static func advance(_ date: Date, _ g: Granularity, by n: Int, calendar: Calendar = .current) -> Date {
        let component: Calendar.Component = (g == .day) ? .day : (g == .week ? .weekOfYear : .month)
        return calendar.date(byAdding: component, value: n, to: date) ?? date
    }

    /// The `[start, end)` instant range spanned by `count` periods ending at `now`.
    public static func range(endingAt now: Date, count: Int, granularity g: Granularity, calendar: Calendar = .current) -> Range<Date> {
        let last = periodStart(now, g, calendar: calendar)
        let first = advance(last, g, by: -(count - 1), calendar: calendar)
        let end = advance(last, g, by: 1, calendar: calendar)
        return first..<end
    }

    /// `count` consecutive buckets (oldest → newest) ending at the period containing `now`.
    public static func buckets(
        todos: [DailyTodo],
        sessions: [FocusSession],
        endingAt now: Date = .now,
        count: Int,
        granularity g: Granularity,
        calendar: Calendar = .current
    ) -> [StatBucket] {
        let last = periodStart(now, g, calendar: calendar)
        var starts: [Date] = []
        for i in stride(from: count - 1, through: 0, by: -1) {
            starts.append(advance(last, g, by: -i, calendar: calendar))
        }
        var map: [Date: StatBucket] = [:]
        for s in starts { map[s] = StatBucket(date: s) }

        func key(for date: Date) -> Date? {
            let s = periodStart(date, g, calendar: calendar)
            return map[s] != nil ? s : nil
        }

        for todo in todos where todo.status != .dropped {
            if let s = key(for: todo.originalPlannedDate) {
                map[s]?.planned += 1
                if todo.isCompleted { map[s]?.completed += 1 }
            }
        }
        for session in sessions {
            if let s = key(for: session.endedAt) {
                map[s]?.focusMinutes += session.minutes
            }
        }
        return starts.compactMap { map[$0] }
    }
}
