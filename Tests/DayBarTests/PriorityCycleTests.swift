import XCTest
@testable import DayBarCore

final class PriorityCycleTests: XCTestCase {
    func testNextCyclesThroughAllLevels() {
        XCTAssertEqual(Priority.none.next, .low)
        XCTAssertEqual(Priority.low.next, .medium)
        XCTAssertEqual(Priority.medium.next, .high)
        XCTAssertEqual(Priority.high.next, .none)
    }

    func testHigherAndLowerClampAtTheEnds() {
        XCTAssertEqual(Priority.high.higher, .high)
        XCTAssertEqual(Priority.none.lower, .none)
        XCTAssertEqual(Priority.low.higher, .medium)
        XCTAssertEqual(Priority.medium.lower, .low)
    }

    func testLevelRoundTripsThroughDigitShortcut() {
        for priority in [Priority.none, .low, .medium, .high] {
            XCTAssertEqual(Priority(level: priority.level), priority)
        }
        XCTAssertNil(Priority(level: 4))
        XCTAssertNil(Priority(level: -1))
    }
}
