import XCTest
@testable import DayBarCore

final class EndOfDayReviewGateTests: XCTestCase {
    private let evening = Date(timeIntervalSince1970: 1_000_000)

    private func present(
        hasReviewedToday: Bool = false,
        totalTodayCount: Int = 3,
        now: Date? = nil,
        snoozedUntil: Date? = nil,
        isFocusSessionRunning: Bool = false
    ) -> Bool {
        EndOfDayReviewGate.shouldPresent(
            hasReviewedToday: hasReviewedToday,
            totalTodayCount: totalTodayCount,
            now: now ?? evening,
            eveningTime: evening,
            snoozedUntil: snoozedUntil,
            isFocusSessionRunning: isFocusSessionRunning
        )
    }

    func testPresentsWhenAllConditionsMet() {
        XCTAssertTrue(present())
    }

    func testDoesNotPresentWhenAlreadyReviewed() {
        XCTAssertFalse(present(hasReviewedToday: true))
    }

    func testDoesNotPresentWithNoTodosToday() {
        XCTAssertFalse(present(totalTodayCount: 0))
    }

    func testDoesNotPresentBeforeEveningTime() {
        XCTAssertFalse(present(now: evening.addingTimeInterval(-60)))
    }

    func testDoesNotPresentWhileSnoozed() {
        let snoozedUntil = evening.addingTimeInterval(3600)
        XCTAssertFalse(present(snoozedUntil: snoozedUntil))
    }

    func testPresentsOnceSnoozeWindowHasPassed() {
        let snoozedUntil = evening.addingTimeInterval(3600)
        XCTAssertTrue(present(now: snoozedUntil.addingTimeInterval(1), snoozedUntil: snoozedUntil))
    }

    func testDoesNotPresentWhileFocusSessionIsRunning() {
        XCTAssertFalse(present(isFocusSessionRunning: true))
    }

    func testPresentsAfterFocusSessionEnds() {
        XCTAssertTrue(present(isFocusSessionRunning: false))
    }
}
