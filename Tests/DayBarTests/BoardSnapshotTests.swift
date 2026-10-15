import XCTest
@testable import DayBarCore

@MainActor
final class BoardSnapshotTests: XCTestCase {
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
                .appendingPathComponent("BoardSnapshotTests-\(UUID().uuidString)")
        )
    }

    func testTodayPartitionsIntoColumns() {
        let todo = state.addTodo(title: "Todo", plannedFor: now, now: now)!
        let wip = state.addTodo(title: "WIP", plannedFor: now, now: now)!
        let done = state.addTodo(title: "Done", plannedFor: now, now: now)!
        state.setBoardStatus(.inProgress, for: wip, now: now)
        state.setBoardStatus(.done, for: done, now: now)

        let snapshot = state.boardSnapshot(for: .today, now: now)

        XCTAssertEqual(snapshot.toDo.map(\.id), [todo.id])
        XCTAssertEqual(snapshot.inProgress.map(\.id), [wip.id])
        XCTAssertEqual(snapshot.done.map(\.id), [done.id])
        XCTAssertEqual(Set(snapshot.open.map(\.id)), [todo.id, wip.id])
        XCTAssertEqual(snapshot.byID[wip.id]?.title, "WIP")
        XCTAssertFalse(snapshot.isEmpty)
    }

    func testSnapshotReflectsMutationsAfterRevisionBump() {
        let todo = state.addTodo(title: "Move me", plannedFor: now, now: now)!
        XCTAssertEqual(state.boardSnapshot(for: .today, now: now).toDo.count, 1)

        state.setBoardStatus(.inProgress, for: todo, now: now)

        let snapshot = state.boardSnapshot(for: .today, now: now)
        XCTAssertTrue(snapshot.toDo.isEmpty)
        XCTAssertEqual(snapshot.inProgress.map(\.id), [todo.id])
    }

    func testAllTasksDoneColumnCoversLastSevenDays() {
        let recent = state.addTodo(title: "Recent", plannedFor: now, now: now)!
        let old = state.addTodo(title: "Old", plannedFor: now, now: now)!
        let tenDaysAgo = cal.date(byAdding: .day, value: -10, to: now)!
        state.toggleComplete(recent, now: now)
        old.completedDate = tenDaysAgo
        old.status = .completed

        let snapshot = state.boardSnapshot(for: .allTasks, now: now.addingTimeInterval(1))

        XCTAssertEqual(snapshot.done.map(\.id), [recent.id])
        XCTAssertTrue(snapshot.open.isEmpty)
    }

    func testProjectDoneColumnIsNewestFirstAndCapped() {
        let project = state.createProject(name: "Big")!
        var completed: [DailyTodo] = []
        for index in 0..<(BoardSnapshot.doneCap + 5) {
            let todo = state.addTodo(title: "T\(index)", plannedFor: now, now: now)!
            state.assign(todo: todo, to: project)
            state.toggleComplete(todo, now: now.addingTimeInterval(TimeInterval(index)))
            completed.append(todo)
        }

        let snapshot = state.boardSnapshot(for: .project(project.id), now: now)

        XCTAssertEqual(snapshot.done.count, BoardSnapshot.doneCap)
        XCTAssertEqual(snapshot.done.first?.id, completed.last?.id)
    }

    func testEmptyScope() {
        XCTAssertTrue(state.boardSnapshot(for: .tomorrow, now: now).isEmpty)
    }
}
