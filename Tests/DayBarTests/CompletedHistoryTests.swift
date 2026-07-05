import XCTest
@testable import DayBarCore

@MainActor
final class CompletedHistoryTests: XCTestCase {
    private var cal: Calendar!
    private var store: DataStore!
    private var state: AppState!

    override func setUp() {
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        store = DataStore(inMemory: true)
        state = AppState(store: store, calendar: cal, schedulesRemindersSync: false, observeSystemEvents: false)
    }

    func testCompletedTodosQueryFiltersByDate() throws {
        let today = cal.startOfDay(for: Date(timeIntervalSince1970: 2_000_000_000))
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!

        let recent = DailyTodo(title: "Recent", plannedForDate: today, status: .completed)
        recent.completedDate = today.addingTimeInterval(3600)
        store.insert(recent)

        let old = DailyTodo(title: "Old", plannedForDate: twoDaysAgo, status: .completed)
        old.completedDate = twoDaysAgo.addingTimeInterval(3600)
        store.insert(old)

        let dropped = DailyTodo(title: "Dropped", plannedForDate: yesterday, status: .dropped)
        dropped.completedDate = yesterday.addingTimeInterval(3600)
        store.insert(dropped)

        store.save()

        let start = cal.date(byAdding: .day, value: -1, to: today)!
        let end = cal.date(byAdding: .day, value: 1, to: today)!
        let results = try store.completedTodos(in: start..<end)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Recent")
    }

    func testCompletedHistoryGroupsByDay() {
        let today = cal.startOfDay(for: Date(timeIntervalSince1970: 2_000_000_000))
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        let a = DailyTodo(title: "A", plannedForDate: yesterday, status: .completed)
        a.completedDate = yesterday.addingTimeInterval(10_800)
        store.insert(a)

        let b = DailyTodo(title: "B", plannedForDate: yesterday, status: .completed)
        b.completedDate = yesterday.addingTimeInterval(14_400)
        store.insert(b)

        let c = DailyTodo(title: "C", plannedForDate: today, status: .completed)
        c.completedDate = today.addingTimeInterval(3600)
        store.insert(c)

        store.save()

        let groups = state.completedHistory(days: 30, now: today.addingTimeInterval(86_400))
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].count, 1)
        XCTAssertEqual(groups[0].todos.first?.title, "C")
        XCTAssertEqual(groups[1].count, 2)
    }
}
