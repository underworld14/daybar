import Foundation

/// One render's worth of task data for a window scope, partitioned into the kanban
/// columns. Built once per `AppState.todosRevision` so board views never fetch in `body`.
@MainActor
public struct BoardSnapshot {
    /// Incomplete tasks (to-do + in progress) in list order.
    public let open: [DailyTodo]
    public let toDo: [DailyTodo]
    public let inProgress: [DailyTodo]
    public let done: [DailyTodo]
    public let byID: [UUID: DailyTodo]

    public static let doneCap = 50

    public static let empty = BoardSnapshot(open: [], done: [])

    public init(open: [DailyTodo], done: [DailyTodo]) {
        let openOnly = open.filter { $0.completedDate == nil }
        self.open = openOnly
        self.toDo = openOnly.filter { !$0.isInProgress }
        self.inProgress = openOnly.filter(\.isInProgress)
        self.done = Array(done.prefix(Self.doneCap))
        var index: [UUID: DailyTodo] = [:]
        for todo in openOnly + self.done { index[todo.id] = todo }
        self.byID = index
    }

    public var isEmpty: Bool { open.isEmpty && done.isEmpty }

    /// Column order (to-do, in progress, done) — drives column-move animations.
    public var orderedIDs: [UUID] { (toDo + inProgress + done).map(\.id) }

    public func todos(in column: BoardColumn) -> [DailyTodo] {
        switch column {
        case .toDo: return toDo
        case .inProgress: return inProgress
        case .done: return done
        }
    }
}
