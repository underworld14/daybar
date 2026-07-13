import XCTest
import UserNotifications
@testable import DayBarCore

@MainActor
final class NotificationSchedulingTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(year: Int = 2026, month: Int = 7, day: Int = 9, hour: Int) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ).date!
    }

    func testBacklogBeforeTwoSchedulesTodayAtTwo() throws {
        let now = date(hour: 10)

        let fireDate = try XCTUnwrap(NotificationScheduling.backlogFireDate(
            agingCount: 1,
            now: now,
            calendar: calendar
        ))
        let interval = try XCTUnwrap(NotificationScheduling.backlogDeliveryInterval(
            agingCount: 1,
            now: now,
            calendar: calendar
        ))

        let expected = try XCTUnwrap(calendar.date(bySettingHour: 14, minute: 0, second: 0, of: now))
        XCTAssertEqual(fireDate, expected)
        XCTAssertEqual(interval, 4 * 60 * 60, accuracy: 0.001)
    }

    func testBacklogAfterTwoSchedulesTomorrowAtTwo() throws {
        let now = date(hour: 15)

        let fireDate = try XCTUnwrap(NotificationScheduling.backlogFireDate(
            agingCount: 2,
            now: now,
            calendar: calendar
        ))
        let interval = try XCTUnwrap(NotificationScheduling.backlogDeliveryInterval(
            agingCount: 2,
            now: now,
            calendar: calendar
        ))

        let todayTwo = try XCTUnwrap(calendar.date(bySettingHour: 14, minute: 0, second: 0, of: now))
        let tomorrowTwo = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: todayTwo))
        XCTAssertEqual(fireDate, tomorrowTwo)
        XCTAssertGreaterThan(interval, 0)
        XCTAssertEqual(interval, tomorrowTwo.timeIntervalSince(now), accuracy: 0.001)
    }

    func testBacklogZeroAgingSchedulesNothing() {
        XCTAssertNil(NotificationScheduling.backlogFireDate(agingCount: 0, now: date(hour: 10), calendar: calendar))
        XCTAssertNil(NotificationScheduling.backlogDeliveryInterval(agingCount: 0, now: date(hour: 15), calendar: calendar))
    }

    func testWillPresentSuppressesBannerWhenPanelOpenForReminders() {
        let options = NotificationScheduling.willPresentOptions(
            identifier: NotificationScheduler.ID.backlog,
            panelVisible: true,
            allowSound: true
        )
        XCTAssertEqual(options, [.list])
    }

    func testWillPresentKeepsBannerForPhaseEndWhenPanelOpen() {
        let options = NotificationScheduling.willPresentOptions(
            identifier: NotificationScheduler.ID.phaseEnd,
            panelVisible: true,
            allowSound: false
        )
        XCTAssertTrue(options.contains(.banner))
        XCTAssertTrue(options.contains(.list))
        XCTAssertFalse(options.contains(.sound))
    }

    func testWillPresentIncludesSoundWhenAllowedAndPanelClosed() {
        let options = NotificationScheduling.willPresentOptions(
            identifier: NotificationScheduler.ID.morning,
            panelVisible: false,
            allowSound: true
        )
        XCTAssertTrue(options.contains(.banner))
        XCTAssertTrue(options.contains(.sound))
        XCTAssertTrue(options.contains(.list))
    }

    func testHabitAnchorsSkipCompletedAndOffScheduleDays() {
        let today = date(hour: 9)
        let completed = HabitTemplate(
            title: "Done",
            createdDate: today,
            anchorHour: 9,
            anchorMinute: 0,
            notifyEnabled: true
        )
        let offSchedule = HabitTemplate(
            title: "Weekend only",
            createdDate: today,
            anchorHour: 9,
            anchorMinute: 0,
            notifyEnabled: true,
            schedulePresetRaw: HabitSchedulePreset.weekends.rawValue
        )
        let pending = HabitTemplate(
            title: "Pending",
            createdDate: today,
            anchorHour: 10,
            anchorMinute: 30,
            notifyEnabled: true
        )
        let completedLog = HabitLog(
            templateId: completed.id,
            day: calendar.startOfDay(for: today),
            completedAt: today,
            status: .completed
        )

        let eligible = NotificationScheduling.habitAnchorTemplates(
            templates: [completed, offSchedule, pending],
            todayLogs: [completedLog],
            now: today,
            calendar: calendar
        )

        XCTAssertEqual(eligible.map(\.id), [pending.id])
    }
}
