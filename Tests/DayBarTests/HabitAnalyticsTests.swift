import XCTest
@testable import DayBarCore

final class HabitAnalyticsTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let templateId = UUID()

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
    }

    private func log(_ offset: Int, status: HabitDayStatus) -> HabitLog {
        HabitLog(templateId: templateId, day: day(offset), status: status)
    }

    func testDailyBucketsCountPlannedAndCompleted() {
        let logs = [
            log(0, status: .completed),
            log(-1, status: .pending),
        ]
        let buckets = HabitAnalytics.buckets(
            logs: logs, endingAt: now, count: 7, granularity: .day, calendar: cal
        )
        XCTAssertEqual(buckets.count, 7)
        XCTAssertEqual(buckets.last?.planned, 1)
        XCTAssertEqual(buckets.last?.completed, 1)
        let prior = buckets[buckets.count - 2]
        XCTAssertEqual(prior.planned, 1)
        XCTAssertEqual(prior.completed, 0)
    }

    func testConsecutiveCompletedStreak() {
        let logs = (0...4).map { log(-$0, status: .completed) }
        let info = HabitAnalytics.streakInfo(logs: logs, templateId: templateId, asOf: now, calendar: cal)
        XCTAssertEqual(info.current, 5)
        XCTAssertEqual(info.best, 5)
    }

    func testPendingTodayDoesNotBreakStreak() {
        let logs = [
            log(0, status: .pending),
            log(-1, status: .completed),
            log(-2, status: .completed),
        ]
        let info = HabitAnalytics.streakInfo(logs: logs, templateId: templateId, asOf: now, calendar: cal)
        XCTAssertEqual(info.current, 2)
    }

    func testGraceAllowsOneMissPerWeek() {
        let logs = [
            log(0, status: .completed),
            log(-1, status: .skipped),
            log(-2, status: .completed),
            log(-3, status: .completed),
        ]
        let info = HabitAnalytics.streakInfo(logs: logs, templateId: templateId, asOf: now, calendar: cal)
        XCTAssertEqual(info.current, 4)
    }

    func testHeatmapReturns28Cells() {
        let logs = [log(0, status: .completed), log(-3, status: .skipped)]
        let cells = HabitAnalytics.heatmap(
            logs: logs, templateId: templateId, days: 28, endingAt: now, calendar: cal
        )
        XCTAssertEqual(cells.count, 28)
        XCTAssertEqual(cells.last?.status, .completed)
    }

    func testMilestoneDetection() {
        XCTAssertTrue(HabitAnalytics.isMilestone(7))
        XCTAssertFalse(HabitAnalytics.isMilestone(6))
    }
}