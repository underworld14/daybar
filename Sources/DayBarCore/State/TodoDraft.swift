import Foundation

/// A new task with everything a composer knows up front, so it is created with a single
/// insert + save (instead of add → assign → set status, each reloading the lists).
public struct TodoDraft: Sendable {
    public var title: String
    public var priority: Priority
    public var plannedFor: Date?
    public var projectID: UUID?
    public var column: BoardColumn

    public init(
        title: String,
        priority: Priority = .none,
        plannedFor: Date? = nil,
        projectID: UUID? = nil,
        column: BoardColumn = .toDo
    ) {
        self.title = title
        self.priority = priority
        self.plannedFor = plannedFor
        self.projectID = projectID
        self.column = column
    }
}
