import XCTest
@testable import DayBarCore

/// Task edits skip the full `refresh` (rollover, habits, review prompt, Reminders pull) but
/// must still leave every list correct — including across a day boundary.
@MainActor
final class LightweightMutationTests: XCTestCase {
    private var cal: Calendar!
    private var store: DataStore!
    private var state: AppState!
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    override func setUp() {
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        store = DataStore(inMemory: true)
        state = AppState(
            store: store, calendar: cal,
            schedulesRemindersSync: false, observeSystemEvents: false,
            notesRoot: FileManager.default.temporaryDirectory
                .appendingPathComponent("LightweightMutationTests-\(UUID().uuidString)")
        )
    }

    func testMutationAfterDayChangeStillRollsOver() {
        let stale = state.addTodo(title: "Stale", plannedFor: now, now: now)!
        let other = state.addTodo(title: "Other", plannedFor: now, now: now)!
        let nextDay = cal.date(byAdding: .day, value: 1, to: now)!

        // No explicit refresh: the mutation itself must notice the new day.
        state.toggleComplete(other, now: nextDay)

        XCTAssertEqual(stale.status, .carriedOver)
        XCTAssertEqual(state.carriedTodos.map(\.id), [stale.id])
        XCTAssertTrue(state.todayTodos.contains(where: { $0.id == other.id }),
                      "completing a carried task pulls it into today")
    }

    func testTodayListStaysCorrectAcrossAddRenameDropUndo() {
        let a = state.addTodo(title: "A", plannedFor: now, now: now)!
        let b = state.addTodo(title: "B", plannedFor: now, now: now)!
        XCTAssertEqual(Set(state.todayTodos.map(\.id)), [a.id, b.id])

        state.rename(a, to: "A2", now: now)
        XCTAssertEqual(state.todayTodos.first(where: { $0.id == a.id })?.title, "A2")

        state.drop(b, now: now)
        XCTAssertEqual(state.todayTodos.map(\.id), [a.id])

        state.performUndo(token: b.id.uuidString, now: now)
        XCTAssertEqual(Set(state.todayTodos.map(\.id)), [a.id, b.id])
    }

    func testRevisionIncreasesOnEveryTaskMutation() {
        let todo = state.addTodo(title: "Count", plannedFor: now, now: now)!
        var last = state.todosRevision

        state.setPriority(todo, .high, now: now)
        XCTAssertGreaterThan(state.todosRevision, last)
        last = state.todosRevision

        state.advanceTodo(todo, now: now)
        XCTAssertGreaterThan(state.todosRevision, last)
        last = state.todosRevision

        state.delay(todo, now: now)
        XCTAssertGreaterThan(state.todosRevision, last)
    }

    func testChecklistProgressTracksAddAndToggle() {
        let todo = state.addTodo(title: "With list", plannedFor: now, now: now)!
        XCTAssertNil(state.checklistProgress[todo.id])

        let first = state.addChecklistItem(to: todo, title: "One", now: now)!
        _ = state.addChecklistItem(to: todo, title: "Two", now: now)
        XCTAssertEqual(state.checklistProgress[todo.id], ChecklistProgress(done: 0, total: 2))

        let before = state.todosRevision
        state.toggleChecklistItem(first, now: now)
        XCTAssertEqual(state.checklistProgress[todo.id], ChecklistProgress(done: 1, total: 2))
        XCTAssertGreaterThan(state.todosRevision, before)
    }

    func testOpenTaskCountCountsIncompleteNonDroppedTasks() {
        let project = state.createProject(name: "Work")!
        let open = state.addTodo(title: "Open", plannedFor: now, now: now)!
        let done = state.addTodo(title: "Done", plannedFor: now, now: now)!
        let dropped = state.addTodo(title: "Dropped", plannedFor: now, now: now)!
        for todo in [open, done, dropped] { state.assign(todo: todo, to: project) }
        XCTAssertEqual(state.openTaskCount(forProject: project.id), 3)

        state.toggleComplete(done, now: now)
        state.drop(dropped, now: now)

        XCTAssertEqual(state.openTaskCount(forProject: project.id), 1)
        XCTAssertEqual(state.openTaskCount(forProject: UUID()), 0)
    }
}
