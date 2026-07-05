import XCTest
import CoreGraphics
@testable import DayBarCore

@MainActor
final class IdleBreakSkipTests: XCTestCase {
    private var store: DataStore!
    private var state: AppState!
    private let t0 = Date(timeIntervalSince1970: 2_000_000_000)

    override func setUp() {
        store = DataStore(inMemory: true)
        state = AppState(store: store, schedulesRemindersSync: false, observeSystemEvents: false)
        UserDefaults.standard.set(true, forKey: PreferenceKeys.skipBreakWhenIdle)
        UserDefaults.standard.set(45, forKey: PreferenceKeys.idleSkipMinutes)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: PreferenceKeys.skipBreakWhenIdle)
        UserDefaults.standard.removeObject(forKey: PreferenceKeys.idleSkipMinutes)
        IdleMonitor.secondsSinceLastInput = {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        }
    }

    func testSkipBreakAdvancesToWork() {
        let engine = PomodoroEngine(config: PomodoroConfig(shortBreakDuration: 300, autoStartNext: false))
        engine.start(.work, now: t0)
        engine.tick(now: t0.addingTimeInterval(1500))
        XCTAssertTrue(engine.phase.isBreak)
        engine.skip(now: t0.addingTimeInterval(1500))
        XCTAssertEqual(engine.phase, .work)
    }

    func testEvaluateIdleBreakSkipStartsWorkWhenAway() {
        UserDefaults.standard.set(30, forKey: PreferenceKeys.idleSkipMinutes)
        state.pomodoro.config = PomodoroConfig(workDuration: 60, shortBreakDuration: 300, autoStartNext: false)
        state.pomodoro.start(.work, now: t0)
        state.pomodoro.tick(now: t0.addingTimeInterval(60))
        XCTAssertTrue(state.pomodoro.phase.isBreak)

        let away = t0.addingTimeInterval(60 + 31 * 60)
        IdleMonitor.secondsSinceLastInput = { 31 * 60 }
        state.evaluateIdleBreakSkip(now: away)

        XCTAssertEqual(state.pomodoro.phase, .work)
        XCTAssertTrue(state.pomodoro.isRunning)
    }

    func testEvaluateIdleBreakSkipDoesNotFireBeforeThreshold() {
        state.pomodoro.config = PomodoroConfig(workDuration: 60, shortBreakDuration: 300, autoStartNext: false)
        state.pomodoro.start(.work, now: t0)
        state.pomodoro.tick(now: t0.addingTimeInterval(60))

        let soon = t0.addingTimeInterval(120)
        IdleMonitor.secondsSinceLastInput = { 600 }
        state.evaluateIdleBreakSkip(now: soon)

        XCTAssertTrue(state.pomodoro.phase.isBreak)
        XCTAssertFalse(state.pomodoro.isRunning)
    }

    func testSkipBreakAndStartWorkFromUI() {
        state.pomodoro.config = PomodoroConfig(workDuration: 60, shortBreakDuration: 300, autoStartNext: false)
        state.pomodoro.start(.work, now: t0)
        state.pomodoro.tick(now: t0.addingTimeInterval(60))

        state.skipBreakAndStartWork(now: t0.addingTimeInterval(1600))

        XCTAssertEqual(state.pomodoro.phase, .work)
        XCTAssertTrue(state.pomodoro.isRunning)
    }
}
