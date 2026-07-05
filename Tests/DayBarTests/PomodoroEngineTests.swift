import XCTest
@testable import DayBarCore

@MainActor
final class PomodoroEngineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000_000)

    func testNaturalCompletionReportsFullElapsed() {
        let engine = PomodoroEngine(config: PomodoroConfig(workDuration: 60))
        var captured: (PomodoroPhase, TimeInterval, Bool)?
        engine.onPhaseEnd = { phase, elapsed, natural, _ in captured = (phase, elapsed, natural) }

        engine.start(.work, now: t0)
        engine.tick(now: t0.addingTimeInterval(60)) // reach the end

        XCTAssertEqual(captured?.0, .work)
        XCTAssertEqual(captured?.1 ?? -1, 60, accuracy: 0.5)
        XCTAssertEqual(captured?.2, true)
    }

    func testSkipReportsPartialElapsedNotCompleted() {
        let engine = PomodoroEngine(config: PomodoroConfig(workDuration: 60))
        var captured: (PomodoroPhase, TimeInterval, Bool)?
        engine.onPhaseEnd = { phase, elapsed, natural, _ in captured = (phase, elapsed, natural) }

        engine.start(.work, now: t0)
        engine.skip(now: t0.addingTimeInterval(20)) // 20s in, 40s remaining

        XCTAssertEqual(captured?.0, .work)
        XCTAssertEqual(captured?.1 ?? -1, 20, accuracy: 1.0)
        XCTAssertEqual(captured?.2, false)
    }

    func testSkipWhilePausedExcludesPausedTime() {
        let engine = PomodoroEngine(config: PomodoroConfig(workDuration: 60))
        var captured: (PomodoroPhase, TimeInterval, Bool)?
        engine.onPhaseEnd = { phase, elapsed, natural, _ in captured = (phase, elapsed, natural) }

        engine.start(.work, now: t0)
        engine.pause(now: t0.addingTimeInterval(20))   // 20s focused, 40s remaining, endDate=nil
        engine.skip(now: t0.addingTimeInterval(50))    // 30s of pause passes; still only 20s focused

        XCTAssertEqual(captured?.1 ?? -1, 20, accuracy: 1.0)
        XCTAssertEqual(captured?.2, false)
    }

    func testWorkAdvancesToBreakOnCompletion() {
        let engine = PomodoroEngine(config: PomodoroConfig(workDuration: 60, autoStartNext: false))
        engine.start(.work, now: t0)
        engine.tick(now: t0.addingTimeInterval(60))
        XCTAssertTrue(engine.phase.isBreak)
    }

    func testSkipBreakAdvancesToWork() {
        let engine = PomodoroEngine(config: PomodoroConfig(workDuration: 60, shortBreakDuration: 300, autoStartNext: false))
        engine.start(.work, now: t0)
        engine.tick(now: t0.addingTimeInterval(60))
        XCTAssertTrue(engine.phase.isBreak)
        engine.skip(now: t0.addingTimeInterval(120))
        XCTAssertEqual(engine.phase, .work)
    }
}
