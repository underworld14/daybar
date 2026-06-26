import Foundation

/// How often a habit should appear on the today list.
public enum HabitSchedulePreset: String, Codable, CaseIterable, Sendable {
    case everyDay
    case weekdays
    case weekends
    case custom
}

/// Schedule helpers for habit materialization, analytics, and Reminders recurrence.
public enum HabitSchedule {
    public static let allDaysMask = 0b1111111

    public static func preset(for template: HabitTemplate) -> HabitSchedulePreset {
        HabitSchedulePreset(rawValue: template.schedulePresetRaw) ?? .everyDay
    }

    public static func weekdayMask(for template: HabitTemplate) -> Int {
        let mask = template.scheduleWeekdayMask
        return mask == 0 ? maskForPreset(.everyDay) : mask
    }

    public static func maskForPreset(_ preset: HabitSchedulePreset) -> Int {
        switch preset {
        case .everyDay: return allDaysMask
        case .weekdays: return 0b0111110  // Mon–Fri
        case .weekends: return 0b1000001  // Sun, Sat
        case .custom: return allDaysMask
        }
    }

    public static func isScheduled(
        _ template: HabitTemplate,
        on day: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let normalized = calendar.startOfDay(for: day)
        let createdDay = calendar.startOfDay(for: template.createdDate)
        guard normalized >= createdDay else { return false }

        let preset = preset(for: template)
        let mask: Int
        if preset == .custom {
            mask = template.scheduleWeekdayMask == 0 ? allDaysMask : template.scheduleWeekdayMask
        } else {
            mask = maskForPreset(preset)
        }
        let weekday = calendar.component(.weekday, from: normalized)
        let bit = 1 << (weekday - 1)
        return (mask & bit) != 0
    }

    /// EventKit `EKWeekday` values (Sunday = 1 … Saturday = 7) for a weekday bitmask.
    public static func eventKitWeekdays(mask: Int) -> [Int] {
        (1...7).filter { (mask & (1 << ($0 - 1))) != 0 }
    }

    public static func displayLabel(for template: HabitTemplate) -> String {
        switch preset(for: template) {
        case .everyDay: return "Every day"
        case .weekdays: return "Weekdays"
        case .weekends: return "Weekends"
        case .custom: return "Custom"
        }
    }
}