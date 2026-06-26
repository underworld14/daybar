import XCTest
@testable import DayBarCore

final class DayMathTests: XCTestCase {
    private func cal(_ tz: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tz)!
        return c
    }

    func testSameDayIsZero() {
        let c = cal("UTC")
        let morning = c.date(from: DateComponents(year: 2025, month: 6, day: 1, hour: 8))!
        let night = c.date(from: DateComponents(year: 2025, month: 6, day: 1, hour: 23))!
        XCTAssertEqual(DayMath.dayDifference(from: morning, to: night, calendar: c), 0)
    }

    func testConsecutiveDays() {
        let c = cal("UTC")
        let a = c.date(from: DateComponents(year: 2025, month: 6, day: 1, hour: 23))!
        let b = c.date(from: DateComponents(year: 2025, month: 6, day: 2, hour: 1))!
        XCTAssertEqual(DayMath.dayDifference(from: a, to: b, calendar: c), 1)
    }

    func testAcrossDSTSpringForward() {
        let c = cal("America/New_York")
        let before = c.date(from: DateComponents(year: 2025, month: 3, day: 8, hour: 12))!
        let after = c.date(from: DateComponents(year: 2025, month: 3, day: 10, hour: 12))!
        XCTAssertEqual(DayMath.dayDifference(from: before, to: after, calendar: c), 2)
    }

    func testTimezoneChangesDayBoundary() {
        let utc = cal("UTC")
        let tokyo = cal("Asia/Tokyo")
        let ref = utc.date(from: DateComponents(year: 2025, month: 6, day: 1, hour: 0))!
        let lateUTC = utc.date(from: DateComponents(year: 2025, month: 6, day: 1, hour: 23, minute: 30))!
        XCTAssertEqual(DayMath.dayDifference(from: ref, to: lateUTC, calendar: utc), 0)
        XCTAssertEqual(DayMath.dayDifference(from: ref, to: lateUTC, calendar: tokyo), 1)
    }
}
