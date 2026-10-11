import XCTest
@testable import DayBarCore

@MainActor
final class PlannedDateTests: XCTestCase {
    private var cal: Calendar!
    private var store: DataStore!
    private var state: AppState!

    override func setUp() {
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        store = DataStore(inMemory: true)
        state = AppState(
            store: store, calendar: cal,
            schedulesRemindersSync: false, observeSystemEvents: false,
            notesRoot: FileManager.default.temporaryDirectory
                .appendingPathComponent("PlannedDateTests-\(UUID().uuidString)")
        )
    }

    private var now: Date { Date(timeIntervalSince1970: 2_000_000_000) }

    func testSetPlannedDateNormalizesToStartOfDay() {
        let todo = state.addTodo(title: "T", plannedFor: now, now: now)!
        let later = cal.date(byAdding: .hour, value: 9, to: now)!

        state.setPlannedDate(todo, to: later, now: now)

        XCTAssertEqual(todo.plannedForDate, cal.startOfDay(for: later))
    }

    func testSetPlannedDatePreservesCompletedTask() {
        let todo = state.addTodo(title: "Done", plannedFor: now, now: now)!
        state.setBoardStatus(.done, for: todo, now: now)
        let completedDate = todo.completedDate

        state.setPlannedDate(todo, to: cal.date(byAdding: .day, value: 3, to: now)!, now: now)

        XCTAssertEqual(todo.completedDate, completedDate)
        XCTAssertEqual(todo.status, .completed)
    }

    func testSetPlannedDateClearsSnooze() {
        let todo = state.addTodo(title: "S", plannedFor: now, now: now)!
        todo.status = .snoozed
        todo.snoozedUntil = cal.date(byAdding: .day, value: 1, to: now)!

        state.setPlannedDate(todo, to: cal.date(byAdding: .day, value: 2, to: now)!, now: now)

        XCTAssertEqual(todo.status, .planned)
        XCTAssertNil(todo.snoozedUntil)
    }
}
