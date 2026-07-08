import XCTest
@testable import DayBarCore

final class TickingSoundGateTests: XCTestCase {
    func testPlaysDuringRunningWorkPhaseWhenEnabled() {
        XCTAssertTrue(TickingSoundGate.shouldPlay(preferenceEnabled: true, isWorkPhase: true, isRunning: true))
    }

    func testSilentWhenPreferenceDisabled() {
        XCTAssertFalse(TickingSoundGate.shouldPlay(preferenceEnabled: false, isWorkPhase: true, isRunning: true))
    }

    func testSilentOutsideWorkPhase() {
        XCTAssertFalse(TickingSoundGate.shouldPlay(preferenceEnabled: true, isWorkPhase: false, isRunning: true))
    }

    func testSilentWhenWorkPhasePaused() {
        XCTAssertFalse(TickingSoundGate.shouldPlay(preferenceEnabled: true, isWorkPhase: true, isRunning: false))
    }
}
