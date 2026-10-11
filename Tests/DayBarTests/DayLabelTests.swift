import XCTest
@testable import DayBarCore

final class DayLabelTests: XCTestCase {
    private let cal = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testTodayIsNil() {
        XCTAssertNil(DayLabel.relative(now, now: now, calendar: cal))
    }

    func testTomorrow() {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(DayLabel.relative(tomorrow, now: now, calendar: cal), "Tomorrow")
    }

    func testYesterday() {
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        XCTAssertEqual(DayLabel.relative(yesterday, now: now, calendar: cal), "Yesterday")
    }

    func testOtherDayIsDayMonth() {
        let other = cal.date(byAdding: .day, value: 5, to: now)!
        let label = DayLabel.relative(other, now: now, calendar: cal)
        XCTAssertFalse(label!.contains("Tomorrow"))
        XCTAssertFalse(label!.isEmpty)
    }
}
