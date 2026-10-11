import XCTest
@testable import DayBarCore

@MainActor
final class ProjectTests: XCTestCase {
    private var store: DataStore!

    override func setUp() {
        store = DataStore(inMemory: true)
    }

    private func makeTodo(
        _ title: String,
        plannedFor: Date = .now,
        priority: Priority = .medium,
        completed: Bool = false,
        projectID: UUID? = nil
    ) -> DailyTodo {
        let todo = DailyTodo(
            title: title,
            plannedForDate: plannedFor,
            completedDate: completed ? Date.now : nil,
            status: completed ? .completed : .planned,
            priority: priority,
            projectID: projectID
        )
        store.insert(todo)
        return todo
    }

    func testAllProjectsSortsBySortOrderThenCreatedDate() throws {
        let late = Project(name: "Later", sortOrder: 0)
        late.createdDate = Date.now.addingTimeInterval(100)
        let early = Project(name: "Earlier", sortOrder: 0)
        early.createdDate = Date.now
        let first = Project(name: "First", sortOrder: -1)

        store.insert(late)
        store.insert(early)
        store.insert(first)

        let names = try store.allProjects().map(\.name)
        XCTAssertEqual(names, ["First", "Earlier", "Later"])
    }

    func testDeleteProjectNullsProjectIDOnAssignedTodos() throws {
        let project = store.insert(Project(name: "Side Quest"))
        let a = makeTodo("A", projectID: project.id)
        let b = makeTodo("B", projectID: nil)

        store.delete(project)
        _ = store.save()

        XCTAssertNil(a.projectID)
        XCTAssertNil(b.projectID)
        XCTAssertTrue(try store.allProjects().isEmpty)
        XCTAssertEqual(try store.allTodos().map(\.title).sorted(), ["A", "B"])
    }

    func testTodosInProjectExcludesDroppedAndSortsIncompleteFirst() throws {
        let project = store.insert(Project(name: "Work"))
        let pid = project.id
        let done = makeTodo("Done", priority: .high, completed: true, projectID: pid)
        let highOpen = makeTodo("High open", priority: .high, projectID: pid)
        let lowOpen = makeTodo("Low open", priority: .low, projectID: pid)
        let dropped = makeTodo("Dropped", projectID: pid)
        dropped.status = .dropped
        let otherProject = makeTodo("Other", projectID: nil)

        let todos = try store.todos(inProject: pid)

        XCTAssertEqual(todos.map(\.title), ["High open", "Low open", "Done"])
        XCTAssertFalse(todos.contains(where: { $0.id == dropped.id }))
        XCTAssertFalse(todos.contains(where: { $0.id == otherProject.id }))
        XCTAssertTrue(done.isCompleted)
        XCTAssertTrue(highOpen.isInProgress == false)
    }

    func testTodosInProjectReturnsEmptyForUnknownID() throws {
        XCTAssertTrue(try store.todos(inProject: UUID()).isEmpty)
    }
}
