import XCTest
@testable import DayBarCore

@MainActor
final class BoardStatusTests: XCTestCase {
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
                .appendingPathComponent("BoardStatusTests-\(UUID().uuidString)")
        )
    }

    private func makeTodo(_ title: String, plannedFor: Date, now: Date) -> DailyTodo {
        state.addTodo(title: title, plannedFor: plannedFor, now: now)!
    }

    func testDoneSetsCompletedDateAndStatus() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let todo = makeTodo("Ship", plannedFor: now, now: now)

        state.setBoardStatus(.done, for: todo, now: now)

        XCTAssertNotNil(todo.completedDate)
        XCTAssertEqual(todo.status, .completed)
    }

    func testToDoAfterDoneClearsCompletedDate() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let todo = makeTodo("Ship", plannedFor: now, now: now)
        state.setBoardStatus(.done, for: todo, now: now)

        state.setBoardStatus(.toDo, for: todo, now: now)

        XCTAssertNil(todo.completedDate)
        XCTAssertEqual(todo.status, .planned)
    }

    func testToDoForPastDatedTodoYieldsCarriedOver() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        let todo = makeTodo("Old", plannedFor: yesterday, now: now)

        state.setBoardStatus(.toDo, for: todo, now: now)

        XCTAssertNil(todo.completedDate)
        XCTAssertEqual(todo.status, .carriedOver)
    }

    func testInProgressClearsCompleted() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let todo = makeTodo("WIP", plannedFor: now, now: now)
        state.setBoardStatus(.done, for: todo, now: now)

        state.setBoardStatus(.inProgress, for: todo, now: now)

        XCTAssertNil(todo.completedDate)
        XCTAssertEqual(todo.status, .inProgress)
    }

    func testAllTasksScopeExcludesCompletedAndDropped() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let open = makeTodo("Open", plannedFor: now, now: now)
        let done = makeTodo("Done", plannedFor: now, now: now)
        state.setBoardStatus(.done, for: done, now: now)
        let dropped = makeTodo("Dropped", plannedFor: now, now: now)
        state.drop(dropped, now: now)

        let all = state.windowTodos(for: .allTasks, now: now)

        XCTAssertEqual(all.map(\.id), [open.id])
    }

    func testAssignLinksProjectAndDeleteProjectUnassigns() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let todo = makeTodo("Task", plannedFor: now, now: now)
        let project = state.createProject(name: "Side Quest")!

        state.assign(todo: todo, to: project)
        XCTAssertEqual(todo.projectID, project.id)
        XCTAssertEqual(state.projects.first(where: { $0.id == project.id })?.name, "Side Quest")
        XCTAssertEqual(state.windowTodos(for: .project(project.id), now: now).map(\.id), [todo.id])

        state.deleteProject(project)
        XCTAssertNil(todo.projectID)
        XCTAssertTrue(state.projects.isEmpty)
        XCTAssertTrue(state.windowTodos(for: .project(project.id), now: now).isEmpty)
        // The task itself survives.
        XCTAssertEqual(state.windowTodos(for: .allTasks, now: now).map(\.id), [todo.id])
    }

    func testScopeKeys() {
        let id = UUID()
        XCTAssertEqual(state.scopeKey(for: .today), "today")
        XCTAssertEqual(state.scopeKey(for: .tomorrow), "tomorrow")
        XCTAssertEqual(state.scopeKey(for: .allTasks), "all")
        XCTAssertEqual(state.scopeKey(for: .project(id)), "project:\(id.uuidString)")
    }
}
