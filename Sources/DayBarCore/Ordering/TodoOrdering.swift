import Foundation

/// Comparators for task lists. `manual` is the user's drag order (one global order shared by
/// every view); ties fall back to creation time, then id, so the order is deterministic.
public enum TodoOrdering {
    /// User order: `sortOrder`, then `createdDate`, then `id`.
    public static func manual(_ lhs: DailyTodo, _ rhs: DailyTodo) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.createdDate != rhs.createdDate { return lhs.createdDate < rhs.createdDate }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Day/project lists: incomplete tasks first, each group in manual order.
    public static func grouped(_ lhs: DailyTodo, _ rhs: DailyTodo) -> Bool {
        let lhsDone = lhs.completedDate != nil
        let rhsDone = rhs.completedDate != nil
        if lhsDone != rhsDone { return !lhsDone }
        return manual(lhs, rhs)
    }

    /// The pre-manual-order sort (priority high→low, then oldest first). Used once to
    /// backfill `sortOrder`, and to order batches pulled from Reminders.
    public static func legacy(_ lhs: DailyTodo, _ rhs: DailyTodo) -> Bool {
        if lhs.priorityRaw != rhs.priorityRaw { return lhs.priorityRaw > rhs.priorityRaw }
        if lhs.createdDate != rhs.createdDate { return lhs.createdDate < rhs.createdDate }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
