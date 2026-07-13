import XCTest
@testable import DayBarCore

@MainActor
final class TodoDetailTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(false, forKey: PreferenceKeys.remindersSyncEnabled)
        UserDefaults.standard.set(false, forKey: PreferenceKeys.remindersHabitsSyncEnabled)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: PreferenceKeys.remindersSyncEnabled)
        UserDefaults.standard.removeObject(forKey: PreferenceKeys.remindersHabitsSyncEnabled)
        super.tearDown()
    }

    private func makeState(store: DataStore) -> AppState {
        AppState(
            store: store,
            calendar: cal,
            remindersProvider: MockRemindersProvider(),
            schedulesRemindersSync: false,
            observeSystemEvents: false
        )
    }

    func testUpdateNotesPersistsAndTrims() throws {
        let store = DataStore(inMemory: true)
        let appState = makeState(store: store)
        let todo = try XCTUnwrap(appState.addTodo(title: "Task", now: now))

        appState.updateNotes(todo, to: "  review checklist  \n", now: now)
        XCTAssertEqual(todo.notes, "review checklist")

        appState.updateNotes(todo, to: "review checklist", now: now)
        XCTAssertEqual(todo.notes, "review checklist")

        appState.updateNotes(todo, to: "   ", now: now)
        XCTAssertEqual(todo.notes, "")
    }

    func testChecklistCRUD() throws {
        let store = DataStore(inMemory: true)
        let appState = makeState(store: store)
        let todo = try XCTUnwrap(appState.addTodo(title: "Ship feature", now: now))

        let a = try XCTUnwrap(appState.addChecklistItem(to: todo, title: "Write tests", now: now))
        let b = try XCTUnwrap(appState.addChecklistItem(to: todo, title: "  Open PR  ", now: now))
        XCTAssertNil(appState.addChecklistItem(to: todo, title: "   ", now: now))

        var items = appState.checklistItems(for: todo)
        XCTAssertEqual(items.map(\.title), ["Write tests", "Open PR"])
        XCTAssertEqual(items.map(\.sortOrder), [0, 1])

        appState.toggleChecklistItem(a, now: now)
        XCTAssertTrue(a.isCompleted)

        appState.renameChecklistItem(b, to: "Merge PR", now: now)
        XCTAssertEqual(b.title, "Merge PR")

        appState.deleteChecklistItem(a, now: now)
        items = appState.checklistItems(for: todo)
        XCTAssertEqual(items.map(\.title), ["Merge PR"])
    }

    func testDeleteTodoCascadesChecklist() throws {
        let store = DataStore(inMemory: true)
        let appState = makeState(store: store)
        let todo = try XCTUnwrap(appState.addTodo(title: "Parent", now: now))
        _ = appState.addChecklistItem(to: todo, title: "Child", now: now)
        XCTAssertEqual(try store.allChecklistItems().count, 1)

        store.delete(todo)
        store.save()
        XCTAssertEqual(try store.allChecklistItems().count, 0)
        XCTAssertEqual(try store.allTodos().count, 0)
    }

    func testCompletingChecklistDoesNotCompleteTodo() throws {
        let store = DataStore(inMemory: true)
        let appState = makeState(store: store)
        let todo = try XCTUnwrap(appState.addTodo(title: "Parent", now: now))
        let item = try XCTUnwrap(appState.addChecklistItem(to: todo, title: "Step", now: now))

        appState.toggleChecklistItem(item, now: now)
        XCTAssertTrue(item.isCompleted)
        XCTAssertFalse(todo.isCompleted)
        XCTAssertEqual(todo.status, .planned)
    }
}
