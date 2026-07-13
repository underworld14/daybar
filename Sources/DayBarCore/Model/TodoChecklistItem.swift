import Foundation
import SwiftData

/// A local checklist sub-item belonging to a `DailyTodo` (matched by `todoId`).
/// Not synced to Apple Reminders.
@Model
public final class TodoChecklistItem {
    @Attribute(.unique) public var id: UUID = UUID()
    public var todoId: UUID = UUID()
    public var title: String = ""
    public var isCompleted: Bool = false
    public var sortOrder: Int = 0

    public init(
        id: UUID = UUID(),
        todoId: UUID,
        title: String,
        isCompleted: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.todoId = todoId
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
    }
}
