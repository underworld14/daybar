import Foundation

/// Completed tasks grouped by the calendar day they were finished.
public struct DayHistoryGroup: Identifiable {
    public var id: Date { date }
    public let date: Date
    public let todos: [DailyTodo]

    public var count: Int { todos.count }
}
