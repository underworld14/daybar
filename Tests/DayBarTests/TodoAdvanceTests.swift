import XCTest
@testable import DayBarCore

@MainActor
final class TodoAdvanceTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(false, forKey: PreferenceKeys.remindersSyncEnabled)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: PreferenceKeys.remindersSyncEnabled)
        super.tearDown()
    }

    func testAdvanceTodoCyclesPlannedInProgressCompleted() throws {
        let store = DataStore(inMemory: true)
        let appState = AppState(store: store, calendar: cal, remindersProvider: MockRemindersProvider())
        guard let todo = appState.addTodo(title: "Task", now: now) else {
            XCTFail("Expected todo")
            return
        }

        XCTAssertEqual(todo.status, .planned)
        appState.advanceTodo(todo, now: now)
        XCTAssertEqual(todo.status, .inProgress)
        XCTAssertFalse(todo.isCompleted)

        appState.advanceTodo(todo, now: now)
        XCTAssertEqual(todo.status, .completed)
        XCTAssertTrue(todo.isCompleted)

        appState.advanceTodo(todo, now: now)
        XCTAssertEqual(todo.status, .planned)
        XCTAssertFalse(todo.isCompleted)
    }

    func testResetTodoFromInProgress() throws {
        let store = DataStore(inMemory: true)
        let appState = AppState(store: store, calendar: cal, remindersProvider: MockRemindersProvider())
        guard let todo = appState.addTodo(title: "Task", now: now) else {
            XCTFail("Expected todo")
            return
        }

        appState.advanceTodo(todo, now: now)
        appState.resetTodo(todo, now: now)
        XCTAssertEqual(todo.status, .planned)
    }

    func testInProgressCountsTowardActiveNotDone() throws {
        let store = DataStore(inMemory: true)
        let appState = AppState(store: store, calendar: cal, remindersProvider: MockRemindersProvider())
        _ = appState.addTodo(title: "A", now: now)
        guard let todo = appState.addTodo(title: "B", now: now) else { return }

        appState.advanceTodo(todo, now: now)
        XCTAssertEqual(appState.inProgressTodayCount, 1)
        XCTAssertEqual(appState.completedTodayCount, 0)
    }
}