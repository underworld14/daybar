import XCTest
@testable import DayBarCore

@MainActor
final class HabitScheduleTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testEveryDayIsScheduled() {
        let template = HabitTemplate(title: "Daily", createdDate: now)
        XCTAssertTrue(HabitSchedule.isScheduled(template, on: now, calendar: cal))
    }

    func testWeekdaysSkipsSaturday() {
        var saturday = cal.startOfDay(for: now)
        while cal.component(.weekday, from: saturday) != 7 {
            saturday = cal.date(byAdding: .day, value: 1, to: saturday)!
        }
        let template = HabitTemplate(
            title: "Weekday",
            createdDate: saturday,
            schedulePresetRaw: HabitSchedulePreset.weekdays.rawValue
        )
        XCTAssertFalse(HabitSchedule.isScheduled(template, on: saturday, calendar: cal))
    }

    func testCustomMask() {
        let template = HabitTemplate(
            title: "Mon only",
            createdDate: now,
            schedulePresetRaw: HabitSchedulePreset.custom.rawValue,
            scheduleWeekdayMask: 1 << 1
        )
        var monday = cal.startOfDay(for: now)
        while cal.component(.weekday, from: monday) != 2 {
            monday = cal.date(byAdding: .day, value: 1, to: monday)!
        }
        XCTAssertTrue(HabitSchedule.isScheduled(template, on: monday, calendar: cal))
    }

    func testEngineSkipsOffDays() throws {
        var saturday = cal.startOfDay(for: now)
        while cal.component(.weekday, from: saturday) != 7 {
            saturday = cal.date(byAdding: .day, value: 1, to: saturday)!
        }
        let store = DataStore(inMemory: true)
        let template = HabitTemplate(
            title: "Weekday",
            createdDate: saturday,
            schedulePresetRaw: HabitSchedulePreset.weekdays.rawValue
        )
        store.insert(template)
        store.save()

        let engine = HabitEngine(store: store, calendar: cal)
        engine.materializeIfNeeded(now: saturday)

        XCTAssertEqual(try store.habitLogs(on: saturday, calendar: cal).count, 0)
    }
}