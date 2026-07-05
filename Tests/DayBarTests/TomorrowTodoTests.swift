import XCTest
@testable import DayBarCore

@MainActor
final class TomorrowTodoTests: XCTestCase {
    private var cal: Calendar!
    private var store: DataStore!
    private var state: AppState!

    override func setUp() {
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        store = DataStore(inMemory: true)
        state = AppState(store: store, calendar: cal, schedulesRemindersSync: false, observeSystemEvents: false)
    }

    func testAddTodoForTomorrow() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let tomorrow = DayMath.nextDay(now, calendar: cal)

        let todo = state.addTodo(title: "Prep slides", plannedFor: tomorrow, now: now)
        XCTAssertNotNil(todo)
        XCTAssertEqual(todo?.plannedForDate, tomorrow)
        XCTAssertEqual(todo?.originalPlannedDate, tomorrow)
        XCTAssertTrue(state.tomorrowTodos.contains(where: { $0.title == "Prep slides" }))
        XCTAssertTrue(state.todayTodos.isEmpty)
    }

    func testTomorrowTodoAppearsInTodayAfterMidnight() {
        let evening = Date(timeIntervalSince1970: 2_000_000_000)
        let tomorrow = DayMath.nextDay(evening, calendar: cal)
        _ = state.addTodo(title: "Morning standup", plannedFor: tomorrow, now: evening)

        state.refresh(now: tomorrow.addingTimeInterval(3600))

        XCTAssertTrue(state.todayTodos.contains(where: { $0.title == "Morning standup" }))
        XCTAssertTrue(state.tomorrowTodos.isEmpty)
    }
}
