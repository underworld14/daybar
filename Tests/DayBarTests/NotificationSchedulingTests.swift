import XCTest
@testable import DayBarCore

@MainActor
final class NotificationSchedulingTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(hour: Int) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: 9,
            hour: hour
        ).date!
    }

    func testBacklogBeforeTwoSchedulesFutureDelivery() throws {
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

        XCTAssertGreaterThan(fireDate, now)
        XCTAssertEqual(interval, 4 * 60 * 60, accuracy: 0.001)
    }

    func testBacklogAfterTwoWithAgingDeliversImmediately() throws {
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

        XCTAssertLessThan(fireDate, now)
        XCTAssertEqual(interval, 1, accuracy: 0.001)
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
