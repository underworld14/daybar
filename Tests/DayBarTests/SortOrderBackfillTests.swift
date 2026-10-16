import XCTest
@testable import DayBarCore

/// The upgrade to manual order must keep every list looking exactly as it did.
@MainActor
final class SortOrderBackfillTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func legacyStore() -> DataStore {
        let store = DataStore(inMemory: true)
        let today = Calendar.current.startOfDay(for: now)
        let titlesAndPriorities: [(String, Priority)] = [("low", .low), ("high", .high), ("none", .none), ("medium", .medium)]
        for (offset, (title, priority)) in titlesAndPriorities.enumerated() {
            store.insert(DailyTodo(
                title: title, createdDate: now.addingTimeInterval(TimeInterval(offset)),
                plannedForDate: today, originalPlannedDate: today, priority: priority
            ))
        }
        // Simulate a store from before manual ordering.
        try! store.appMeta().didBackfillTodoSortOrder = false
        store.save()
        return store
    }

    func testBackfillReproducesThePriorityOrder() throws {
        let store = legacyStore()
        store.backfillTodoSortOrderIfNeeded()
        XCTAssertEqual(try store.todos(on: now).map(\.title), ["high", "medium", "low", "none"])
        XCTAssertTrue(try store.appMeta().didBackfillTodoSortOrder)
    }

    func testBackfillRunsOnce() throws {
        let store = legacyStore()
        store.backfillTodoSortOrderIfNeeded()
        let todo = try XCTUnwrap(try store.todos(on: now).last)
        todo.sortOrder = -1
        store.save()

        store.backfillTodoSortOrderIfNeeded()

        XCTAssertEqual(try store.todos(on: now).first?.title, "none")
    }

    func testBackupWithoutSortOrderImportsInLegacyOrder() throws {
        let source = legacyStore()
        source.backfillTodoSortOrderIfNeeded()
        var raw = try JSONSerialization.jsonObject(with: try JSONStore.encode(source.exportSnapshot())) as! [String: Any]
        raw["todos"] = (raw["todos"] as! [[String: Any]]).map { todo in
            var stripped = todo
            stripped.removeValue(forKey: "sortOrder")
            return stripped
        }
        let snapshot = try JSONStore.decode(try JSONSerialization.data(withJSONObject: raw))
        XCTAssertNil(snapshot.todos.first?.sortOrder)

        let target = DataStore(inMemory: true)
        XCTAssertTrue(target.importSnapshot(snapshot))

        XCTAssertEqual(try target.todos(on: now).map(\.title), ["high", "medium", "low", "none"])
    }

    func testRoundTripKeepsSortOrderAndFocusTask() throws {
        let store = DataStore(inMemory: true)
        let todo = DailyTodo(title: "kept", plannedForDate: now, originalPlannedDate: now, sortOrder: 4242)
        store.insert(todo)
        store.insert(FocusSession(endedAt: now, minutes: 25, completed: true, todoID: todo.id))
        store.save()

        let decoded = try JSONStore.decode(try JSONStore.encode(store.exportSnapshot()))

        XCTAssertEqual(decoded.todos.first?.sortOrder, 4242)
        XCTAssertEqual(decoded.focusSessions?.first?.todoID, todo.id)
        XCTAssertEqual(decoded.todos.first?.makeModel().sortOrder, 4242)
    }

    func testOldFocusSessionBackupDecodesWithoutTask() throws {
        let dto = FocusSessionDTO(id: UUID(), endedAt: now, minutes: 25, completed: true)
        var raw = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(dto)) as! [String: Any]
        raw.removeValue(forKey: "todoID")
        let decoded = try JSONDecoder().decode(FocusSessionDTO.self, from: try JSONSerialization.data(withJSONObject: raw))
        XCTAssertNil(decoded.todoID)
    }
}
