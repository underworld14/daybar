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
}