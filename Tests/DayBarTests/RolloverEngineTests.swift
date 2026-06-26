import XCTest
@testable import DayBarCore

@MainActor
final class RolloverEngineTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
    }

    func testMarksPastDueIncompleteAsCarriedOver() throws {
        let store = DataStore(inMemory: true)
        let todo = DailyTodo(title: "x", plannedForDate: day(-1), originalPlannedDate: day(-1))
        store.insert(todo); store.save()

        let engine = RolloverEngine(store: store, calendar: cal)
        XCTAssertTrue(engine.performRolloverIfNeeded(now: now))
        XCTAssertEqual(todo.status, .carriedOver)
        XCTAssertEqual(try store.appMeta().lastProcessedDay, cal.startOfDay(for: now))
    }

    func testIdempotentSameDay() throws {
        let store = DataStore(inMemory: true)
        let todo = DailyTodo(title: "x", plannedForDate: day(-2), originalPlannedDate: day(-2))
        store.insert(todo); store.save()

        let engine = RolloverEngine(store: store, calendar: cal)
        XCTAssertTrue(engine.performRolloverIfNeeded(now: now))
        XCTAssertFalse(engine.performRolloverIfNeeded(now: now))
        XCTAssertEqual(todo.status, .carriedOver)
    }

    func testCompletedNotCarried() throws {
        let store = DataStore(inMemory: true)
        let done = DailyTodo(title: "done", plannedForDate: day(-1), originalPlannedDate: day(-1),
                             completedDate: day(-1), status: .completed)
        store.insert(done); store.save()
        _ = RolloverEngine(store: store, calendar: cal).performRolloverIfNeeded(now: now)
        XCTAssertEqual(done.status, .completed)
    }

    func testMultiDayGapCatchesUp() throws {
        let store = DataStore(inMemory: true)
        let todo = DailyTodo(title: "old", plannedForDate: day(-3), originalPlannedDate: day(-3))
        store.insert(todo)
        let meta = try store.appMeta()
        meta.lastProcessedDay = day(-3)
        store.save()

        _ = RolloverEngine(store: store, calendar: cal).performRolloverIfNeeded(now: now)
        XCTAssertEqual(todo.status, .carriedOver)
        XCTAssertEqual(todo.carryOverAgeInDays(asOf: now, calendar: cal), 3)
    }
}
