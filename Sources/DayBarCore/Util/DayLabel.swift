import Foundation

/// Short human label for a task's planned day, relative to `now`.
public enum DayLabel {
    /// `nil` when `day` is today (no chip needed).
    public static func relative(
        _ day: Date, now: Date, calendar: Calendar = .current
    ) -> String? {
        let d = DayMath.startOfDay(day, calendar: calendar)
        let t = DayMath.startOfDay(now, calendar: calendar)
        if d == t { return nil }
        if d == DayMath.nextDay(now, calendar: calendar) { return "Tomorrow" }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: t) ?? t
        if d == yesterday { return "Yesterday" }
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.setLocalizedDateFormatFromTemplate("d MMM")
        return fmt.string(from: d)
    }
}
