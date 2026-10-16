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

    /// A planned day spelled out for date pickers: a relative word when one fits
    /// ("Today", "Tomorrow", "Yesterday") plus the calendar date, and whether it is past.
    public struct Long: Equatable, Sendable {
        /// "Tomorrow", or the date itself ("Fri 17 Oct") when no relative word applies.
        public let title: String
        /// The date shown next to a relative title ("Fri 17 Oct"); `nil` when `title` is it.
        public let detail: String?
        public let isOverdue: Bool

        /// "Tomorrow, Fri 17 Oct" / "Fri 17 Oct".
        public var text: String { detail.map { "\(title), \($0)" } ?? title }
    }

    public static func long(
        _ day: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> Long {
        let d = DayMath.startOfDay(day, calendar: calendar)
        let t = DayMath.startOfDay(now, calendar: calendar)
        let offset = DayMath.dayDifference(from: t, to: d, calendar: calendar)
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = locale
        fmt.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: d) == calendar.component(.year, from: t)
        fmt.setLocalizedDateFormatFromTemplate(sameYear ? "EEE d MMM" : "EEE d MMM yyyy")
        let date = fmt.string(from: d)
        switch offset {
        case 0: return Long(title: "Today", detail: date, isOverdue: false)
        case 1: return Long(title: "Tomorrow", detail: date, isOverdue: false)
        case -1: return Long(title: "Yesterday", detail: date, isOverdue: true)
        default: return Long(title: date, detail: nil, isOverdue: offset < 0)
        }
    }
}
