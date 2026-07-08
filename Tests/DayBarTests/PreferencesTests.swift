import XCTest
@testable import DayBarCore

final class PreferencesTests: XCTestCase {
    private let keys = [
        PreferenceKeys.workMinutes, PreferenceKeys.shortBreakMinutes,
        PreferenceKeys.longBreakMinutes, PreferenceKeys.cyclesBeforeLongBreak,
        PreferenceKeys.autoStartNext, PreferenceKeys.soundEnabled,
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
}
