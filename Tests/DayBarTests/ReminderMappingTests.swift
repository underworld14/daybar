import XCTest
@testable import DayBarCore

final class ReminderMappingTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let today = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))

    func testPriorityMapping() {
        XCTAssertEqual(ReminderMapping.priority(fromEventKit: 1), .low)
        XCTAssertEqual(ReminderMapping.priority(fromEventKit: 5), .medium)
        XCTAssertEqual(ReminderMapping.priority(fromEventKit: 9), .high)
    }

    func testMakeTodoFromCompletedReminder() {
        let dto = ReminderDTO(
            externalIdentifier: "r1",
            title: "Buy milk",
            dueDate: today,
            isCompleted: true,
            completionDate: now,
            calendarIdentifier: "list-1"
        )
        let todo = ReminderMapping.makeTodo(from: dto, today: now, calendar: cal)
        XCTAssertEqual(todo.source, .reminders)
        XCTAssertEqual(todo.externalIdentifier, "r1")
        XCTAssertTrue(todo.isCompleted)
        XCTAssertEqual(todo.externalModifiedAt, dto.modifiedAt)
    }

    func testMakeTodoPreservesExternalModifiedAt() {
        let modified = Date(timeIntervalSince1970: 1_700_000_100)
        let dto = ReminderDTO(
            externalIdentifier: "r-mod",
            title: "Task",
            dueDate: today,
            calendarIdentifier: "list-1",
            modifiedAt: modified
        )
        let todo = ReminderMapping.makeTodo(from: dto, today: now, calendar: cal)
        XCTAssertEqual(todo.externalModifiedAt, modified)
    }

    func testApplyUpdatesExistingTodo() {
        let todo = DailyTodo(title: "Old", plannedForDate: today, originalPlannedDate: today)
        let dto = ReminderDTO(
            externalIdentifier: "r2",
            title: "Updated",
            dueDate: today,
            calendarIdentifier: "list-1",
            modifiedAt: now
        )
        ReminderMapping.apply(dto, to: todo, today: now, calendar: cal)
        XCTAssertEqual(todo.title, "Updated")
        XCTAssertEqual(todo.source, .reminders)
        XCTAssertEqual(todo.externalIdentifier, "r2")
    }

    func testDroppedNotReopenedByIncompleteRemote() {
        let todo = DailyTodo(
            title: "Dropped",
            plannedForDate: today,
            originalPlannedDate: today,
            status: .dropped,
            source: .reminders,
            externalIdentifier: "r-drop"
        )
        let dto = ReminderDTO(
            externalIdentifier: "r-drop",
            title: "Remote title",
            dueDate: today,
            isCompleted: false,
            calendarIdentifier: "list-1",
            modifiedAt: now
        )
        ReminderMapping.apply(dto, to: todo, today: now, calendar: cal)
        XCTAssertEqual(todo.status, .dropped)
        XCTAssertEqual(todo.title, "Remote title")
        XCTAssertEqual(todo.externalModifiedAt, now)
    }

    func testDtoRoundTrip() {
        let todo = DailyTodo(
            title: "Task",
            plannedForDate: today,
            originalPlannedDate: today,
            source: .reminders,
            externalIdentifier: "abc"
        )
        let dto = ReminderMapping.dto(from: todo)
        XCTAssertEqual(dto?.title, "Task")
        XCTAssertEqual(dto?.externalIdentifier, "abc")
    }

    func testNotesRoundTrip() {
        let todo = DailyTodo(
            title: "Task",
            notes: "Ship checklist notes",
            plannedForDate: today,
            originalPlannedDate: today,
            source: .reminders,
            externalIdentifier: "notes-1"
        )
        let dto = ReminderMapping.dto(from: todo)
        XCTAssertEqual(dto?.notes, "Ship checklist notes")

        let made = ReminderMapping.makeTodo(
            from: ReminderDTO(
                externalIdentifier: "notes-2",
                title: "From remote",
                notes: "Remote body",
                dueDate: today,
                calendarIdentifier: "list-1"
            ),
            today: now,
            calendar: cal
        )
        XCTAssertEqual(made.notes, "Remote body")

        let existing = DailyTodo(title: "Old", plannedForDate: today, originalPlannedDate: today)
        ReminderMapping.apply(
            ReminderDTO(
                externalIdentifier: "notes-3",
                title: "Updated",
                notes: "Applied notes",
                dueDate: today,
                calendarIdentifier: "list-1",
                modifiedAt: now
            ),
            to: existing,
            today: now,
            calendar: cal
        )
        XCTAssertEqual(existing.notes, "Applied notes")
    }
}
