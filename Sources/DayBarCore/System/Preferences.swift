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
    public static let tickingSoundEnabled = "sound.tickingEnabled"
    public static let gardenSoundEnabled = "sound.gardenEnabled"

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
    public static let radioVolume = "radio.volume"

    public static let moodAIEnabled = "mood.aiEnabled"
    public static let escalationIntensity = "escalation.intensity" // 0=gentle, 1=standard
    public static let quietHoursEnabled = "notify.quietHoursEnabled"
    public static let quietHoursStartHour = "notify.quietHoursStartHour"
    public static let respectSystemFocus = "notify.respectSystemFocus"
    public static let awayStartDate = "away.startDate"
    public static let awayEndDate = "away.endDate"
    public static let weeklyDigestEnabled = "notify.weeklyDigestEnabled"
    public static let weeklyDigestLastFiredDay = "notify.weeklyDigestLastFiredDay"
}

/// Typed reads of the app preferences. Getters bake in the same defaults SettingsView
/// declares, so values are correct even before the user ever opens Settings.
public enum Preferences {
    private static var defaults: UserDefaults { .standard }

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
    /// Ambient clock tick during an active focus session — off by default since it's a
    /// polarizing preference, unlike the phase-end ring which everyone benefits from.
    public static var tickingSoundEnabled: Bool { defaults.bool(forKey: PreferenceKeys.tickingSoundEnabled) }
    /// Soft growth/harvest chimes in the focus garden — on by default when global sound is on.
    public static var gardenSoundEnabled: Bool {
        defaults.object(forKey: PreferenceKeys.gardenSoundEnabled) as? Bool ?? true
    }

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

    public static var radioVolume: Float {
        get {
            guard defaults.object(forKey: PreferenceKeys.radioVolume) != nil else { return 0.6 }
            return defaults.float(forKey: PreferenceKeys.radioVolume)
        }
        set { defaults.set(newValue, forKey: PreferenceKeys.radioVolume) }
    }

    // MARK: - Mood

    /// User-level override, separate from device/OS eligibility: some users may have an
    /// eligible device with Apple Intelligence on but still not want this feature to run.
    public static var moodAIEnabled: Bool { boolOrTrue(PreferenceKeys.moodAIEnabled) }

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

    public static var escalationIntensity: Int {
        get { defaults.object(forKey: PreferenceKeys.escalationIntensity) as? Int ?? 0 }
        set { defaults.set(newValue, forKey: PreferenceKeys.escalationIntensity) }
    }

    public static var escalationThresholds: EscalationThresholds {
        escalationIntensity >= 1
            ? EscalationThresholds.standard
            : .gentle
    }

    public static var quietHoursEnabled: Bool {
        get { defaults.object(forKey: PreferenceKeys.quietHoursEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: PreferenceKeys.quietHoursEnabled) }
    }

    public static var quietHoursStartHour: Int {
        get { intOrSet(PreferenceKeys.quietHoursStartHour, 21) }
        set { defaults.set(newValue, forKey: PreferenceKeys.quietHoursStartHour) }
    }

    public static var respectSystemFocus: Bool {
        get { defaults.object(forKey: PreferenceKeys.respectSystemFocus) as? Bool ?? true }
        set { defaults.set(newValue, forKey: PreferenceKeys.respectSystemFocus) }
    }

    public static var awayStartDate: Date? {
        get { defaults.object(forKey: PreferenceKeys.awayStartDate) as? Date }
        set { defaults.set(newValue, forKey: PreferenceKeys.awayStartDate) }
    }

    public static var awayEndDate: Date? {
        get { defaults.object(forKey: PreferenceKeys.awayEndDate) as? Date }
        set { defaults.set(newValue, forKey: PreferenceKeys.awayEndDate) }
    }

    /// True when `day` falls in the user-marked away range (inclusive start, exclusive end+1day).
    public static func isAway(on day: Date, calendar: Calendar = .current) -> Bool {
        guard let start = awayStartDate, let end = awayEndDate else { return false }
        let d = calendar.startOfDay(for: day)
        let s = calendar.startOfDay(for: start)
        let e = calendar.startOfDay(for: end)
        return d >= s && d <= e
    }

    public static var weeklyDigestEnabled: Bool {
        get { defaults.object(forKey: PreferenceKeys.weeklyDigestEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: PreferenceKeys.weeklyDigestEnabled) }
    }

    public static var weeklyDigestLastFiredDay: Date? {
        get { defaults.object(forKey: PreferenceKeys.weeklyDigestLastFiredDay) as? Date }
        set { defaults.set(newValue, forKey: PreferenceKeys.weeklyDigestLastFiredDay) }
    }

    /// Soften audible feedback when quiet hours apply (and optionally when Focus/DND is on).
    public static func shouldPlayAudibleAlerts(now: Date = .now, calendar: Calendar = .current) -> Bool {
        if quietHoursEnabled {
            let hour = calendar.component(.hour, from: now)
            if hour >= quietHoursStartHour || hour < 6 { return false }
        }
        if respectSystemFocus {
            // Best-effort: macOS Focus / Do Not Disturb preference (may be absent on some OS versions).
            let dnd = UserDefaults(suiteName: "com.apple.ncprefs")?.dictionary(forKey: "dnd_prefs")
            if let enabled = dnd?["dndEnabled"] as? Bool, enabled { return false }
        }
        return true
    }
}
