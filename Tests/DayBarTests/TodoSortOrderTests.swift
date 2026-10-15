import XCTest
@testable import DayBarCore

/// Manual order at the AppState level: priority is a flag, not a sort key.
@MainActor
final class TodoSortOrderTests: XCTestCase {
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
                .appendingPathComponent("TodoSortOrderTests-\(UUID().uuidString)")
        )
    }

    private func add(_ title: String, day: Date? = nil) -> DailyTodo {
        state.addTodo(title: title, plannedFor: day ?? now, now: now)!
    }

    private var todayTitles: [String] { state.todayTodos.map(\.title) }

    func testNewTasksHaveNoPriorityAndLandAtTheBottomAboveCompleted() {
        let done = add("Done")
        state.toggleComplete(done, now: now)
        let a = add("A")
        let b = add("B")

        XCTAssertEqual(a.priority, .none)
        XCTAssertEqual(todayTitles, ["A", "B", "Done"])
        XCTAssertLessThan(a.sortOrder, b.sortOrder)
    }

    func testSettingPriorityDoesNotReorder() {
        _ = add("A")
        let b = add("B")
        state.setPriority(b, .high, now: now)
        XCTAssertEqual(todayTitles, ["A", "B"])
    }

    func testMoveTodoReordersTheVisibleList() {
        _ = add("A"); _ = add("B")
        let c = add("C")

        state.moveTodo(c, toIndex: 0, in: state.todayTodos, now: now)

        XCTAssertEqual(todayTitles, ["C", "A", "B"])
    }

    func testMoveByOffsetAndToTop() {
        let a = add("A"); _ = add("B"); let c = add("C")

        state.moveTodo(a, by: 1, in: state.todayTodos, now: now)
        XCTAssertEqual(todayTitles, ["B", "A", "C"])

        state.moveTodoToTop(c, in: state.todayTodos, now: now)
        XCTAssertEqual(todayTitles, ["C", "B", "A"])
    }

    func testReorderInAProjectKeepsTodaysRelativeOrderOfOtherTasks() {
        let project = state.createProject(name: "P")!
        let a = add("A"); _ = add("B"); let c = add("C")
        state.assign(todo: a, to: project)
        state.assign(todo: c, to: project)

        // In the project only A and C are visible; move C above A.
        let projectList = try! store.todos(inProject: project.id)
        state.moveTodo(c, toIndex: 0, in: projectList, now: now)

        XCTAssertEqual(try! store.todos(inProject: project.id).map(\.title), ["C", "A"])
        XCTAssertEqual(todayTitles, ["C", "A", "B"])
    }

    func testExhaustedGapRenormalizesAndStillMoves() {
        let a = add("A"); let b = add("B"); let c = add("C")
        a.sortOrder = 1
        b.sortOrder = 1 + 1e-12
        c.sortOrder = 9
        store.save()
        state.refresh(now: now)

        state.moveTodo(c, toIndex: 1, in: state.todayTodos, now: now)

        XCTAssertEqual(todayTitles, ["A", "C", "B"])
        XCTAssertGreaterThan(b.sortOrder - a.sortOrder, 1)
    }

    func testDelayAndRescheduleLandAtTheBottomOfTheTargetDay() {
        let tomorrow = DayMath.nextDay(now, calendar: cal)
        _ = add("Tomorrow 1", day: tomorrow)
        let moved = add("Moved")
        _ = add("Tomorrow 2", day: tomorrow)

        state.delay(moved, now: now)
        XCTAssertEqual(state.tomorrowTodos.map(\.title), ["Tomorrow 1", "Tomorrow 2", "Moved"])

        _ = add("Today 1")
        state.reschedule(moved, to: now, now: now)
        XCTAssertEqual(todayTitles, ["Today 1", "Moved"])
    }

    func testCompletedStaysBelowIncompleteWhateverItsOrder() {
        let first = add("First")
        _ = add("Second")
        state.toggleComplete(first, now: now)
        XCTAssertEqual(todayTitles, ["Second", "First"])
    }

    func testDraftCreatesTaskWithProjectAndColumnInOneRevision() {
        let project = state.createProject(name: "Board")!
        let before = state.todosRevision

        let todo = state.addTodo(
            TodoDraft(title: "Ship", priority: .high, plannedFor: now, projectID: project.id, column: .inProgress),
            now: now
        )!

        XCTAssertEqual(state.todosRevision, before + 1)
        XCTAssertEqual(todo.projectID, project.id)
        XCTAssertTrue(todo.isInProgress)
        XCTAssertEqual(todo.priority, .high)
    }

    func testDragTodayTaskIntoTomorrowCountsAsDelayAndLandsAtIndex() {
        let tomorrow = DayMath.nextDay(now, calendar: cal)
        _ = add("T1", day: tomorrow)
        _ = add("T2", day: tomorrow)
        let moved = add("Today task")
        let target = state.tomorrowTodos.filter { $0.completedDate == nil }

        state.moveTodo(moved, toDay: tomorrow, index: 1, in: target, now: now)

        XCTAssertEqual(state.tomorrowTodos.map(\.title), ["T1", "Today task", "T2"])
        XCTAssertEqual(moved.delayCount, 1)
        XCTAssertTrue(state.todayTodos.isEmpty)
    }

    func testDragCarriedTaskIntoTodayRevivesIt() {
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        let carried = add("Old", day: yesterday)
        _ = add("A"); _ = add("B")
        state.refresh(now: now)
        XCTAssertEqual(carried.status, .carriedOver)

        state.moveTodo(carried, toDay: now, index: 0, in: state.todayTodos, now: now)

        XCTAssertEqual(todayTitles, ["Old", "A", "B"])
        XCTAssertEqual(carried.status, .planned)
        XCTAssertTrue(state.carriedTodos.isEmpty)
    }

    func testUndoDropRestoresOriginalPosition() {
        _ = add("A"); let b = add("B"); _ = add("C")
        let original = b.sortOrder

        state.drop(b, now: now)
        state.performUndo(token: b.id.uuidString, now: now)

        XCTAssertEqual(b.sortOrder, original)
        XCTAssertEqual(todayTitles, ["A", "B", "C"])
    }
}
