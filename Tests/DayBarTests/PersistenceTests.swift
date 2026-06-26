import XCTest
@testable import DayBarCore

@MainActor
final class PersistenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testInsertAndQueryToday() throws {
        let store = DataStore(inMemory: true)
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        store.insert(DailyTodo(title: "a", plannedForDate: today, originalPlannedDate: today))
        store.save()

        let todays = try store.todos(on: now)
        XCTAssertEqual(todays.count, 1)
        XCTAssertEqual(todays.first?.title, "a")
    }

    func testOverdueQueryExcludesDropped() throws {
        let store = DataStore(inMemory: true)
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))!
        store.insert(DailyTodo(title: "keep", plannedForDate: yesterday, originalPlannedDate: yesterday))
        store.insert(DailyTodo(title: "gone", plannedForDate: yesterday, originalPlannedDate: yesterday, status: .dropped))
        store.save()

        let overdue = try store.overdueIncompleteTodos(before: now)
        XCTAssertEqual(overdue.map(\.title), ["keep"])
    }

    func testJSONRoundTrip() throws {
        let model = DailyTodo(title: "x", plannedForDate: now, originalPlannedDate: now, status: .carriedOver)
        let snapshot = StoreSnapshotDTO(todos: [TodoDTO(model)], meta: MetaDTO(lastProcessedDay: now))
        let data = try JSONStore.encode(snapshot)
        let decoded = try JSONStore.decode(data)
        XCTAssertEqual(decoded.todos.count, 1)
        XCTAssertEqual(decoded.todos.first?.statusRaw, TodoStatus.carriedOver.rawValue)
        XCTAssertEqual(decoded.meta?.lastProcessedDay, now)
    }

    func testImportSnapshotReplacesAll() throws {
        let store = DataStore(inMemory: true)
        store.insert(DailyTodo(title: "old", plannedForDate: now, originalPlannedDate: now))
        store.save()

        let fresh = TodoDTO(DailyTodo(title: "new", plannedForDate: now, originalPlannedDate: now))
        store.importSnapshot(StoreSnapshotDTO(todos: [fresh]))

        let all = try store.allTodos()
        XCTAssertEqual(all.map(\.title), ["new"])
    }
}
