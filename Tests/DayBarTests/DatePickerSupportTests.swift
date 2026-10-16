import XCTest
@testable import DayBarCore

/// DayLabel.long, QuickDatePresets and MonthGrid: the pieces behind the date popover.
final class DatePickerSupportTests: XCTestCase {
    private func calendar(firstWeekday: Int = 1) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = firstWeekday
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 10))!
    }

    private let english = Locale(identifier: "en_GB")

    // MARK: DayLabel.long

    func testLongLabelUsesRelativeWordsAndDate() {
        let cal = calendar()
        let now = date(2026, 10, 16, cal: cal) // Friday
        XCTAssertEqual(DayLabel.long(now, now: now, calendar: cal, locale: english).text, "Today, Fri 16 Oct")
        let tomorrow = DayLabel.long(date(2026, 10, 17, cal: cal), now: now, calendar: cal, locale: english)
        XCTAssertEqual(tomorrow.title, "Tomorrow")
        XCTAssertEqual(tomorrow.detail, "Sat 17 Oct")
        XCTAssertFalse(tomorrow.isOverdue)
    }

    func testLongLabelForPastAndFarDays() {
        let cal = calendar()
        let now = date(2026, 10, 16, cal: cal)
        let yesterday = DayLabel.long(date(2026, 10, 15, cal: cal), now: now, calendar: cal, locale: english)
        XCTAssertEqual(yesterday.title, "Yesterday")
        XCTAssertTrue(yesterday.isOverdue)
        let past = DayLabel.long(date(2026, 10, 2, cal: cal), now: now, calendar: cal, locale: english)
        XCTAssertNil(past.detail)
        XCTAssertTrue(past.isOverdue)
        let nextYear = DayLabel.long(date(2027, 1, 4, cal: cal), now: now, calendar: cal, locale: english)
        XCTAssertTrue(nextYear.title.contains("2027"))
        XCTAssertFalse(nextYear.isOverdue)
    }

    // MARK: QuickDatePresets

    func testPresetsOnAWeekday() {
        let cal = calendar()
        let wednesday = date(2026, 10, 14, cal: cal)
        let presets = QuickDatePresets.presets(now: wednesday, calendar: cal)
        XCTAssertEqual(presets.map(\.kind), [.today, .tomorrow, .thisWeekend, .nextWeek])
        XCTAssertEqual(presets[2].date, cal.startOfDay(for: date(2026, 10, 17, cal: cal)), "coming Saturday")
        XCTAssertEqual(presets[3].date, cal.startOfDay(for: date(2026, 10, 19, cal: cal)), "next Monday")
    }

    func testWeekendPresetIsTodayOnAWeekendAndDuplicatesDrop() {
        let cal = calendar()
        let saturday = date(2026, 10, 17, cal: cal)
        let presets = QuickDatePresets.presets(now: saturday, calendar: cal)
        // "This weekend" would be today, so it is dropped as a duplicate of Today.
        XCTAssertEqual(presets.map(\.kind), [.today, .tomorrow, .nextWeek])
        XCTAssertEqual(presets.last?.date, cal.startOfDay(for: date(2026, 10, 19, cal: cal)))
    }

    func testFridayWeekendIsTomorrowSoItDrops() {
        let cal = calendar()
        let friday = date(2026, 10, 16, cal: cal)
        let presets = QuickDatePresets.presets(now: friday, calendar: cal)
        XCTAssertEqual(presets.map(\.kind), [.today, .tomorrow, .nextWeek])
    }

    func testNextWeekOnAMondayIsAWeekLater() {
        let cal = calendar()
        let monday = date(2026, 10, 12, cal: cal)
        let nextWeek = QuickDatePresets.presets(now: monday, calendar: cal).first { $0.kind == .nextWeek }
        XCTAssertEqual(nextWeek?.date, cal.startOfDay(for: date(2026, 10, 19, cal: cal)))
    }

    // MARK: MonthGrid

    func testGridStartsOnSundayOrMondayFirstWeekday() {
        let sundayFirst = calendar(firstWeekday: 1)
        let october = date(2026, 10, 5, cal: sundayFirst) // 1 Oct 2026 is a Thursday
        let sundayDays = MonthGrid.days(for: october, today: october, calendar: sundayFirst)
        XCTAssertEqual(sundayDays.count, 42)
        XCTAssertEqual(sundayDays.first?.dayNumber, 27, "Sun 27 Sep")
        XCTAssertFalse(sundayDays.first!.isInMonth)
        XCTAssertEqual(sundayDays[4].dayNumber, 1)

        let mondayFirst = calendar(firstWeekday: 2)
        let mondayDays = MonthGrid.days(for: october, today: october, calendar: mondayFirst)
        XCTAssertEqual(mondayDays.first?.dayNumber, 28, "Mon 28 Sep")
        XCTAssertEqual(mondayDays[3].dayNumber, 1)
        XCTAssertEqual(MonthGrid.weekdaySymbols(calendar: mondayFirst).count, 7)
    }

    func testLeapFebruaryAndFlags() {
        let cal = calendar()
        let february = date(2028, 2, 10, cal: cal)
        let days = MonthGrid.days(for: february, today: february, calendar: cal)
        XCTAssertEqual(days.filter(\.isInMonth).count, 29)
        let today = days.first(where: \.isToday)
        XCTAssertEqual(today?.dayNumber, 10)
        XCTAssertTrue(days.first(where: { $0.isInMonth && $0.dayNumber == 9 })!.isPast)
        XCTAssertFalse(days.first(where: { $0.isInMonth && $0.dayNumber == 11 })!.isPast)
    }

    func testShiftMonths() {
        let cal = calendar()
        let jan31 = date(2027, 1, 31, cal: cal)
        let next = MonthGrid.shift(jan31, by: 1, calendar: cal)
        XCTAssertEqual(cal.component(.month, from: next), 2)
        XCTAssertEqual(cal.component(.day, from: next), 1)
    }
}
