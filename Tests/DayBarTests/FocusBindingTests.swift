import XCTest
@testable import DayBarCore

/// "Now" focus: starting focus on a task binds the Pomodoro session to it.
@MainActor
final class FocusBindingTests: XCTestCase {
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
                .appendingPathComponent("FocusBindingTests-\(UUID().uuidString)")
        )
        state.pomodoro.config.autoStartNext = false
    }

    override func tearDown() {
        state.pomodoro.stop(now: now)
        super.tearDown()
    }

    private var workDuration: TimeInterval { state.pomodoro.config.workDuration }

    func testStartFocusMarksInProgressBindsAndStartsWork() {
        let todo = state.addTodo(title: "Deep work", plannedFor: now, now: now)!

        state.startFocus(on: todo, now: now)

        XCTAssertTrue(todo.isInProgress)
        XCTAssertEqual(state.focusTodoID, todo.id)
        XCTAssertEqual(state.pomodoro.phase, .work)
        XCTAssertTrue(state.pomodoro.isRunning)
        XCTAssertEqual(state.nowTodos.map(\.id), [todo.id])
    }

    func testNaturalEndRecordsSessionForTheTaskAndCountsIt() throws {
        let todo = state.addTodo(title: "Deep work", plannedFor: now, now: now)!
        state.startFocus(on: todo, now: now)

        state.pomodoro.tick(now: now.addingTimeInterval(workDuration + 1))

        let sessions = try store.allFocusSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.todoID, todo.id)
        XCTAssertEqual(sessions.first?.completed, true)
        XCTAssertEqual(todo.pomodoroCount, 1)
        XCTAssertEqual(state.focusTodoID, todo.id, "binding survives into the break")
    }

    func testStopRecordsSessionWithoutCountingAndUnbinds() throws {
        let todo = state.addTodo(title: "Interrupted", plannedFor: now, now: now)!
        state.startFocus(on: todo, now: now)

        state.stopPomodoro(now: now.addingTimeInterval(600))

        let sessions = try store.allFocusSessions()
        XCTAssertEqual(sessions.first?.todoID, todo.id)
        XCTAssertEqual(sessions.first?.completed, false)
        XCTAssertEqual(todo.pomodoroCount, 0)
        XCTAssertNil(state.focusTodoID)
    }

    func testUndoStopDeletesTheRecordedSession() throws {
        let todo = state.addTodo(title: "Oops", plannedFor: now, now: now)!
        state.startFocus(on: todo, now: now)
        state.stopPomodoro(now: now.addingTimeInterval(600))
        let token = try XCTUnwrap(state.ephemeralBanner?.undoToken)

        state.performUndo(token: token, now: now)

        XCTAssertTrue(try store.allFocusSessions().isEmpty)
    }

    func testFinishedTaskIsUnboundBeforeTheNextFocusPhase() {
        let todo = state.addTodo(title: "Quick", plannedFor: now, now: now)!
        state.startFocus(on: todo, now: now)
        state.pomodoro.tick(now: now.addingTimeInterval(workDuration + 1)) // → break (armed)
        state.toggleComplete(todo, now: now)

        state.skipBreakAndStartWork(now: now.addingTimeInterval(workDuration + 5))

        XCTAssertNil(state.focusTodoID)
        XCTAssertEqual(state.pomodoro.phase, .work)
    }

    func testRefocusingDuringAPhaseRebindsWithoutRestarting() {
        let first = state.addTodo(title: "First", plannedFor: now, now: now)!
        let second = state.addTodo(title: "Second", plannedFor: now, now: now)!
        state.startFocus(on: first, now: now)
        let end = state.pomodoro.endDate

        state.startFocus(on: second, now: now.addingTimeInterval(60))

        XCTAssertEqual(state.focusTodoID, second.id)
        XCTAssertEqual(state.pomodoro.endDate, end)
        XCTAssertEqual(Set(state.nowTodos.map(\.id)), [first.id, second.id])
    }
}
