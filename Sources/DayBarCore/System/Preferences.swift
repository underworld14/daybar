import Foundation

/// UserDefaults keys shared between these typed accessors and the SwiftUI `@AppStorage`
/// bindings in SettingsView (standard suite).
public enum PreferenceKeys {
    public static let workMinutes = "pomodoro.workMinutes"
    public static let shortBreakMinutes = "pomodoro.shortBreakMinutes"
    public static let longBreakMinutes = "pomodoro.longBreakMinutes"
    public static let cyclesBeforeLongBreak = "pomodoro.cyclesBeforeLongBreak"
    public static let autoStartNext = "pomodoro.autoStartNext"
    public static let skipBreakWhenIdle = "pomodoro.skipBreakWhenIdle"
    public static let idleSkipMinutes = "pomodoro.idleSkipMinutes"
    public static let soundEnabled = "sound.enabled"
    public static let soundName = "sound.name"

    public static let morningEnabled = "notify.morningEnabled"
    public static let morningHour = "notify.morningHour"
    public static let morningMinute = "notify.morningMinute"
    public static let eveningEnabled = "notify.eveningEnabled"
    public static let eveningHour = "notify.eveningHour"
    public static let eveningMinute = "notify.eveningMinute"
    public static let phaseEndNotify = "notify.phaseEndEnabled"
    public static let backlogNotify = "notify.backlogEnabled"
    public static let habitNotifyEnabled = "notify.habitAnchorsEnabled"

    public static let remindersSyncEnabled = "reminders.syncEnabled"
    public static let selectedReminderCalendarIDs = "reminders.selectedCalendarIDs"
    public static let remindersIncludeUndated = "reminders.includeUndated"
    public static let remindersPushNewTodos = "reminders.pushNewTodos"
    public static let defaultReminderCalendarID = "reminders.defaultCalendarID"
    public static let remindersHabitsSyncEnabled = "reminders.habitsSyncEnabled"
    public static let selectedHabitReminderCalendarIDs = "reminders.selectedHabitCalendarIDs"
    public static let defaultHabitReminderCalendarID = "reminders.defaultHabitCalendarID"

    public static let radioLastChannelID = "radio.lastChannelID"
    public static let radioWasPlaying = "radio.wasPlaying"
    public static let radioHasUserStarted = "radio.hasUserStarted"
    public static let radioPauseOnFocusEnd = "radio.pauseOnFocusEnd"
}

/// Typed reads of the app preferences. Getters bake in the same defaults SettingsView
/// declares, so values are correct even before the user ever opens Settings.
public enum Preferences {
    private static var defaults: UserDefaults { .standard }

    /// Built-in macOS alert sounds offered in Settings (files under /System/Library/Sounds).
    public static let availableSounds = ["Glass", "Ping", "Submarine", "Funk", "Hero", "Tink", "Pop"]

    public static var workMinutes: Int { intOr(PreferenceKeys.workMinutes, 25) }
    public static var shortBreakMinutes: Int { intOr(PreferenceKeys.shortBreakMinutes, 5) }
    public static var longBreakMinutes: Int { intOr(PreferenceKeys.longBreakMinutes, 15) }
    public static var cyclesBeforeLongBreak: Int { intOr(PreferenceKeys.cyclesBeforeLongBreak, 4) }
    public static var autoStartNext: Bool { defaults.bool(forKey: PreferenceKeys.autoStartNext) }
    public static var skipBreakWhenIdle: Bool {
        defaults.object(forKey: PreferenceKeys.skipBreakWhenIdle) as? Bool ?? true
    }
    public static var idleSkipMinutes: Int { intOr(PreferenceKeys.idleSkipMinutes, 45) }
    public static var soundEnabled: Bool { defaults.object(forKey: PreferenceKeys.soundEnabled) as? Bool ?? true }
    public static var soundName: String { defaults.string(forKey: PreferenceKeys.soundName) ?? "Glass" }

    /// The current Pomodoro configuration assembled from the saved minute values.
    public static var pomodoroConfig: PomodoroConfig {
        PomodoroConfig(
            workDuration: TimeInterval(workMinutes) * 60,
            shortBreakDuration: TimeInterval(shortBreakMinutes) * 60,
            longBreakDuration: TimeInterval(longBreakMinutes) * 60,
            cyclesBeforeLongBreak: max(1, cyclesBeforeLongBreak),
            autoStartNext: autoStartNext
        )
    }

    /// `integer(forKey:)` returns 0 when unset, so map 0 to the declared fallback.
    private static func intOr(_ key: String, _ fallback: Int) -> Int {
        let value = defaults.integer(forKey: key)
        return value == 0 ? fallback : value
    }

    // MARK: - Notifications

    public static var morningEnabled: Bool { boolOrTrue(PreferenceKeys.morningEnabled) }
    public static var morningHour: Int { intOrSet(PreferenceKeys.morningHour, 9) }
    public static var morningMinute: Int { intOrSet(PreferenceKeys.morningMinute, 0) }
    public static var eveningEnabled: Bool { boolOrTrue(PreferenceKeys.eveningEnabled) }
    public static var eveningHour: Int { intOrSet(PreferenceKeys.eveningHour, 18) }
    public static var eveningMinute: Int { intOrSet(PreferenceKeys.eveningMinute, 0) }
    public static var phaseEndNotify: Bool { boolOrTrue(PreferenceKeys.phaseEndNotify) }
    public static var backlogNotify: Bool { boolOrTrue(PreferenceKeys.backlogNotify) }
    public static var habitNotifyEnabled: Bool { boolOrTrue(PreferenceKeys.habitNotifyEnabled) }

    // MARK: - Apple Reminders

    public static var remindersSyncEnabled: Bool {
        defaults.bool(forKey: PreferenceKeys.remindersSyncEnabled)
    }

    public static var selectedReminderCalendarIDs: [String] {
        defaults.stringArray(forKey: PreferenceKeys.selectedReminderCalendarIDs) ?? []
    }

    public static var remindersIncludeUndated: Bool {
        defaults.object(forKey: PreferenceKeys.remindersIncludeUndated) as? Bool ?? true
    }

    public static var remindersPushNewTodos: Bool {
        defaults.bool(forKey: PreferenceKeys.remindersPushNewTodos)
    }

    public static var defaultReminderCalendarID: String? {
        defaults.string(forKey: PreferenceKeys.defaultReminderCalendarID)
    }

    public static var remindersHabitsSyncEnabled: Bool {
        defaults.bool(forKey: PreferenceKeys.remindersHabitsSyncEnabled)
    }

    public static var selectedHabitReminderCalendarIDs: [String] {
        defaults.stringArray(forKey: PreferenceKeys.selectedHabitReminderCalendarIDs) ?? []
    }

    public static var defaultHabitReminderCalendarID: String? {
        defaults.string(forKey: PreferenceKeys.defaultHabitReminderCalendarID)
    }

    // MARK: - Lofi Radio

    public static var radioLastChannelID: String? {
        defaults.string(forKey: PreferenceKeys.radioLastChannelID)
    }

    public static var radioWasPlaying: Bool {
        defaults.bool(forKey: PreferenceKeys.radioWasPlaying)
    }

    public static var radioHasUserStarted: Bool {
        defaults.bool(forKey: PreferenceKeys.radioHasUserStarted)
    }

    public static var radioPauseOnFocusEnd: Bool {
        defaults.object(forKey: PreferenceKeys.radioPauseOnFocusEnd) as? Bool ?? true
    }

    /// Habit list selection, falling back to todo-selected lists when unset.
    public static var effectiveHabitReminderCalendarIDs: [String] {
        let habit = selectedHabitReminderCalendarIDs
        return habit.isEmpty ? selectedReminderCalendarIDs : habit
    }

    /// The evening-review time on `day`, used to gate the end-of-day auto-prompt.
    public static func eveningTime(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: eveningHour, minute: eveningMinute, second: 0, of: day) ?? day
    }

    private static func boolOrTrue(_ key: String) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    /// Like `intOr`, but treats an explicitly-set 0 (midnight / minute 0) as valid.
    private static func intOrSet(_ key: String, _ fallback: Int) -> Int {
        defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
    }
}
