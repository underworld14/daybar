import XCTest
@testable import DayBarCore

final class AnalyticsTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testDailyBucketsCountPlannedAndCompleted() {
        let today = cal.startOfDay(for: now)
        let todos = [
            DailyTodo(title: "a", plannedForDate: today, originalPlannedDate: today, completedDate: today, status: .completed),
            DailyTodo(title: "b", plannedForDate: today, originalPlannedDate: today),
        ]
        let buckets = Analytics.buckets(todos: todos, sessions: [], endingAt: now, count: 7, granularity: .day, calendar: cal)
        XCTAssertEqual(buckets.count, 7)
        let last = buckets.last!
        XCTAssertEqual(last.planned, 2)
        XCTAssertEqual(last.completed, 1)
        XCTAssertEqual(last.completionRate, 0.5, accuracy: 0.001)
    }

    func testFocusMinutesBinByEndedAt() {
        let sessions = [FocusSession(endedAt: now, minutes: 25), FocusSession(endedAt: now, minutes: 5)]
        let buckets = Analytics.buckets(todos: [], sessions: sessions, endingAt: now, count: 3, granularity: .day, calendar: cal)
        XCTAssertEqual(buckets.last?.focusMinutes, 30)
    }

    func testDroppedExcludedFromPlanned() {
        let today = cal.startOfDay(for: now)
        let todos = [DailyTodo(title: "x", plannedForDate: today, originalPlannedDate: today, status: .dropped)]
        let buckets = Analytics.buckets(todos: todos, sessions: [], endingAt: now, count: 1, granularity: .day, calendar: cal)
        XCTAssertEqual(buckets.last?.planned, 0)
    }

    func testWeeklyGranularityGroupsByWeek() {
        let lastWeek = cal.date(byAdding: .day, value: -7, to: now)!
        let todos = [
            DailyTodo(title: "thisweek", plannedForDate: now, originalPlannedDate: now),
            DailyTodo(title: "lastweek", plannedForDate: lastWeek, originalPlannedDate: lastWeek),
        ]
        let buckets = Analytics.buckets(todos: todos, sessions: [], endingAt: now, count: 2, granularity: .week, calendar: cal)
        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets[0].planned, 1) // last week
        XCTAssertEqual(buckets[1].planned, 1) // this week
    }

    func testOutOfRangeItemsIgnored() {
        let longAgo = cal.date(byAdding: .day, value: -100, to: now)!
        let todos = [DailyTodo(title: "old", plannedForDate: longAgo, originalPlannedDate: longAgo)]
        let buckets = Analytics.buckets(todos: todos, sessions: [], endingAt: now, count: 7, granularity: .day, calendar: cal)
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.planned }, 0)
    }
}
