import XCTest
@testable import DayBarCore

final class PreferencesTests: XCTestCase {
    private let keys = [
        PreferenceKeys.workMinutes, PreferenceKeys.shortBreakMinutes,
        PreferenceKeys.longBreakMinutes, PreferenceKeys.cyclesBeforeLongBreak,
        PreferenceKeys.autoStartNext, PreferenceKeys.soundEnabled,
        PreferenceKeys.tickingSoundEnabled, PreferenceKeys.moodAIEnabled,
        PreferenceKeys.escalationIntensity, PreferenceKeys.quietHoursEnabled,
        PreferenceKeys.weeklyDigestEnabled, PreferenceKeys.selectedReminderCalendarIDs,
        PreferenceKeys.selectedHabitReminderCalendarIDs, PreferenceKeys.gardenActionMode,
    ]

    override func setUp() { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }
    override func tearDown() { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }

    func testDefaultsWhenUnset() {
        XCTAssertEqual(Preferences.workMinutes, 25)
        XCTAssertEqual(Preferences.shortBreakMinutes, 5)
        XCTAssertEqual(Preferences.cyclesBeforeLongBreak, 4)
        XCTAssertTrue(Preferences.soundEnabled)
    }

    func testPomodoroConfigBuiltFromPrefs() {
        UserDefaults.standard.set(30, forKey: PreferenceKeys.workMinutes)
        UserDefaults.standard.set(7, forKey: PreferenceKeys.shortBreakMinutes)
        UserDefaults.standard.set(3, forKey: PreferenceKeys.cyclesBeforeLongBreak)
        UserDefaults.standard.set(true, forKey: PreferenceKeys.autoStartNext)

        let config = Preferences.pomodoroConfig
        XCTAssertEqual(config.workDuration, 30 * 60)
        XCTAssertEqual(config.shortBreakDuration, 7 * 60)
        XCTAssertEqual(config.cyclesBeforeLongBreak, 3)
        XCTAssertTrue(config.autoStartNext)
    }

    func testSoundCanBeDisabled() {
        UserDefaults.standard.set(false, forKey: PreferenceKeys.soundEnabled)
        XCTAssertFalse(Preferences.soundEnabled)
    }

    func testAdditionalDefaultsWhenUnset() {
        XCTAssertFalse(Preferences.tickingSoundEnabled)
        XCTAssertTrue(Preferences.moodAIEnabled)
        XCTAssertEqual(Preferences.escalationIntensity, 0)
        XCTAssertFalse(Preferences.quietHoursEnabled)
        XCTAssertFalse(Preferences.weeklyDigestEnabled)
        XCTAssertEqual(Preferences.effectiveHabitReminderCalendarIDs, [])
        XCTAssertEqual(Preferences.gardenActionMode, .automatic)
    }

    func testAdditionalPreferencesReadStoredValues() {
        UserDefaults.standard.set(true, forKey: PreferenceKeys.tickingSoundEnabled)
        UserDefaults.standard.set(false, forKey: PreferenceKeys.moodAIEnabled)
        Preferences.escalationIntensity = 1
        Preferences.quietHoursEnabled = true
        Preferences.weeklyDigestEnabled = true
        UserDefaults.standard.set("manual", forKey: PreferenceKeys.gardenActionMode)

        XCTAssertTrue(Preferences.tickingSoundEnabled)
        XCTAssertFalse(Preferences.moodAIEnabled)
        XCTAssertEqual(Preferences.escalationIntensity, 1)
        XCTAssertEqual(Preferences.escalationThresholds, .standard)
        XCTAssertTrue(Preferences.quietHoursEnabled)
        XCTAssertTrue(Preferences.weeklyDigestEnabled)
        XCTAssertEqual(Preferences.gardenActionMode, .manual)
    }

    func testEffectiveHabitReminderCalendarIDsFallbackAndOverride() {
        UserDefaults.standard.set(["todo-list"], forKey: PreferenceKeys.selectedReminderCalendarIDs)
        XCTAssertEqual(Preferences.effectiveHabitReminderCalendarIDs, ["todo-list"])

        UserDefaults.standard.set(["habit-list"], forKey: PreferenceKeys.selectedHabitReminderCalendarIDs)
        XCTAssertEqual(Preferences.effectiveHabitReminderCalendarIDs, ["habit-list"])
    }
}
