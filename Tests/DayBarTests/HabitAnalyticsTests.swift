import XCTest
@testable import DayBarCore

final class HabitAnalyticsTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let templateId = UUID()

    private var template: HabitTemplate {
        HabitTemplate(id: templateId, title: "Test", createdDate: day(-30))
    }

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
        let info = HabitAnalytics.streakInfo(logs: logs, template: template, asOf: now, calendar: cal)
        XCTAssertEqual(info.current, 5)
        XCTAssertEqual(info.best, 5)
    }

    func testPendingTodayDoesNotBreakStreak() {
        let logs = [
            log(0, status: .pending),
            log(-1, status: .completed),
            log(-2, status: .completed),
        ]
        let info = HabitAnalytics.streakInfo(logs: logs, template: template, asOf: now, calendar: cal)
        XCTAssertEqual(info.current, 2)
    }

    func testGraceAllowsOneMissPerWeek() {
        let logs = [
            log(0, status: .completed),
            log(-1, status: .skipped),
            log(-2, status: .completed),
            log(-3, status: .completed),
        ]
        let info = HabitAnalytics.streakInfo(logs: logs, template: template, asOf: now, calendar: cal)
        XCTAssertEqual(info.current, 4)
    }

    func testHeatmapReturns28Cells() {
        let logs = [log(0, status: .completed), log(-3, status: .skipped)]
        let cells = HabitAnalytics.heatmap(
            logs: logs, template: template, days: 28, endingAt: now, calendar: cal
        )
        XCTAssertEqual(cells.count, 28)
        XCTAssertEqual(cells.last?.status, .completed)
    }

    func testMilestoneDetection() {
        XCTAssertTrue(HabitAnalytics.isMilestone(7))
        XCTAssertFalse(HabitAnalytics.isMilestone(6))
    }

    func testBestStreakPendingDoesNotUseGrace() {
        let logs = [
            log(-2, status: .completed),
            log(-1, status: .pending),
            log(0, status: .completed),
        ]
        let info = HabitAnalytics.streakInfo(logs: logs, template: template, asOf: now, calendar: cal)
        XCTAssertEqual(info.best, 1)
    }

    func testBestStreakSkippedUsesGrace() {
        let logs = [
            log(-2, status: .completed),
            log(-1, status: .skipped),
            log(0, status: .completed),
        ]
        let info = HabitAnalytics.streakInfo(logs: logs, template: template, asOf: now, calendar: cal)
        XCTAssertEqual(info.best, 3)
    }

    func testGraceRemainingAfterSkip() {
        let logs = [log(-1, status: .skipped), log(0, status: .completed)]
        let info = HabitAnalytics.streakInfo(logs: logs, template: template, asOf: now, calendar: cal)
        XCTAssertEqual(info.graceRemaining, 0)
    }

    func testGraceRemainingAfterPendingMiss() {
        let logs = [log(-1, status: .pending), log(0, status: .completed)]
        let info = HabitAnalytics.streakInfo(logs: logs, template: template, asOf: now, calendar: cal)
        XCTAssertEqual(info.current, 1)
        XCTAssertEqual(info.graceRemaining, 0)
    }

    func testHistoricalPendingBreaksCurrentStreak() {
        let logs = [
            log(-2, status: .completed),
            log(-1, status: .pending),
            log(0, status: .completed),
        ]
        let info = HabitAnalytics.streakInfo(logs: logs, template: template, asOf: now, calendar: cal)
        XCTAssertEqual(info.current, 1)
        XCTAssertEqual(info.best, 1)
    }

    func testHeatmapMarksGraceOffStreakPath() {
        let logs = [
            log(-5, status: .skipped),
            log(-4, status: .completed),
            log(0, status: .completed),
        ]
        let cells = HabitAnalytics.heatmap(
            logs: logs, template: template, days: 28, endingAt: now, calendar: cal
        )
        let skippedCell = cells.first { $0.status == .skipped }
        XCTAssertTrue(skippedCell?.usedGrace == true)
    }

    func testWeekdayScheduleSkipsWeekendInStreak() {
        let weekdayTemplate = HabitTemplate(
            id: templateId,
            title: "Weekday",
            createdDate: day(-10),
            schedulePresetRaw: HabitSchedulePreset.weekdays.rawValue
        )
        // Find a Monday as "today" by walking back from now
        var monday = cal.startOfDay(for: now)
        while cal.component(.weekday, from: monday) != 2 {
            monday = cal.date(byAdding: .day, value: -1, to: monday)!
        }
        let fri = cal.date(byAdding: .day, value: -3, to: monday)!
        let logs = [
            HabitLog(templateId: templateId, day: monday, status: .pending),
            HabitLog(templateId: templateId, day: fri, status: .completed),
        ]
        let info = HabitAnalytics.streakInfo(
            logs: logs, template: weekdayTemplate, asOf: monday, calendar: cal
        )
        XCTAssertEqual(info.current, 1)
    }

    /// Regression for the infinite loop: walking the current streak past `createdDate` must
    /// terminate. Pre-creation days are reported "unscheduled", so without a created-date
    /// floor the loop decrements through the calendar without bound. A perfect streak back to
    /// creation is the case that reaches that boundary.
    func testPerfectStreakBackToCreationTerminates() {
        let everyDay = HabitTemplate(id: templateId, title: "Daily", createdDate: day(-6))
        let logs = (0...6).map { log(-$0, status: .completed) }
        let info = HabitAnalytics.streakInfo(logs: logs, template: everyDay, asOf: now, calendar: cal)
        XCTAssertEqual(info.current, 7)
        XCTAssertEqual(info.best, 7)
    }

    func testWeekendScheduleAccumulatesStreakAcrossWeekdayGap() {
        var sunday = cal.startOfDay(for: now)
        while cal.component(.weekday, from: sunday) != 1 {
            sunday = cal.date(byAdding: .day, value: -1, to: sunday)!
        }
        let sat = cal.date(byAdding: .day, value: -1, to: sunday)!
        let prevSun = cal.date(byAdding: .day, value: -7, to: sunday)!
        let prevSat = cal.date(byAdding: .day, value: -8, to: sunday)!
        let template = HabitTemplate(
            id: templateId, title: "Weekend", createdDate: prevSat,
            schedulePresetRaw: HabitSchedulePreset.weekends.rawValue
        )
        let logs = [sunday, sat, prevSun, prevSat].map {
            HabitLog(templateId: templateId, day: $0, status: .completed)
        }
        let info = HabitAnalytics.streakInfo(logs: logs, template: template, asOf: sunday, calendar: cal)
        XCTAssertEqual(info.current, 4, "weekday gap between weekends must not break the streak")
        XCTAssertEqual(info.best, 4)
    }

    func testHeatmapRendersScheduledOffDaysAsNil() {
        let template = HabitTemplate(
            id: templateId, title: "Weekend", createdDate: day(-30),
            schedulePresetRaw: HabitSchedulePreset.weekends.rawValue
        )
        // A stray completed log on an off-day must still render nil: the schedule, not the log, decides.
        var weekday = cal.startOfDay(for: now)
        while [1, 7].contains(cal.component(.weekday, from: weekday)) {
            weekday = cal.date(byAdding: .day, value: -1, to: weekday)!
        }
        let logs = [HabitLog(templateId: templateId, day: weekday, status: .completed)]
        let cells = HabitAnalytics.heatmap(
            logs: logs, template: template, days: 28, endingAt: now, calendar: cal
        )
        let strayCell = cells.first { cal.isDate($0.date, inSameDayAs: weekday) }
        XCTAssertEqual(strayCell?.status, nil)
        for cell in cells where [2, 3, 4, 5, 6].contains(cal.component(.weekday, from: cell.date)) {
            XCTAssertNil(cell.status, "weekday cells must be off for a weekends-only habit")
        }
    }
}