import Foundation

/// One-time conversion from the old priority-driven order to manual `sortOrder` values,
/// so every list looks exactly as it did before the upgrade.
public enum SortOrderBackfill {
    public static func assignLegacyOrder(to todos: [DailyTodo]) {
        let ordered = todos.sorted(by: TodoOrdering.legacy)
        for (todo, value) in zip(ordered, SortOrderMath.spaced(count: ordered.count)) {
            todo.sortOrder = value
        }
    }
}
