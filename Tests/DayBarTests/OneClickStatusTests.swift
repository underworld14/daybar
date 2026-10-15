import XCTest
@testable import DayBarCore

/// The status ring completes in one click; ⌥-click / Start toggles "in progress".
@MainActor
final class OneClickStatusTests: XCTestCase {
    private var cal: Calendar!
    private var state: AppState!
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    override func setUp() {
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        state = AppState(
            store: DataStore(inMemory: true), calendar: cal,
            schedulesRemindersSync: false, observeSystemEvents: false,
            notesRoot: FileManager.default.temporaryDirectory
                .appendingPathComponent("OneClickStatusTests-\(UUID().uuidString)")
        )
    }

    func testToggleCompleteFinishesAPlannedTaskInOneStep() {
        let todo = state.addTodo(title: "One click", plannedFor: now, now: now)!
        state.toggleComplete(todo, now: now)
        XCTAssertTrue(todo.isCompleted)
        XCTAssertEqual(todo.status, .completed)
    }

    func testToggleCompleteFinishesAnInProgressTask() {
        let todo = state.addTodo(title: "Started", plannedFor: now, now: now)!
        state.startTodo(todo, now: now)
        state.toggleComplete(todo, now: now)
        XCTAssertTrue(todo.isCompleted)
    }

    func testStartTodoMarksInProgressAndReopensDoneTasks() {
        let todo = state.addTodo(title: "Again", plannedFor: now, now: now)!
        state.toggleComplete(todo, now: now)

        state.startTodo(todo, now: now)

        XCTAssertTrue(todo.isInProgress)
        XCTAssertNil(todo.completedDate)
        XCTAssertEqual(state.inProgressTodayCount, 1)
    }

    func testToggleInProgressRoundTrips() {
        let todo = state.addTodo(title: "Flip", plannedFor: now, now: now)!
        state.toggleInProgress(todo, now: now)
        XCTAssertTrue(todo.isInProgress)
        state.toggleInProgress(todo, now: now)
        XCTAssertEqual(todo.status, .planned)
    }

    func testCyclePriorityAdvancesOneLevel() {
        let todo = state.addTodo(title: "Flag", priority: .none, plannedFor: now, now: now)!
        state.cyclePriority(todo, now: now)
        XCTAssertEqual(todo.priority, .low)
        state.cyclePriority(todo, now: now)
        XCTAssertEqual(todo.priority, .medium)
    }
}
