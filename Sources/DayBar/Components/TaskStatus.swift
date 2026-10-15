import DayBarCore

/// The three visual states of a task's status ring.
enum TaskStatus: Equatable {
    case toDo, inProgress, done

    init(_ todo: DailyTodo) {
        switch todo.boardColumn {
        case .done: self = .done
        case .inProgress: self = .inProgress
        case .toDo: self = .toDo
        }
    }

    var accessibilityValue: String {
        switch self {
        case .toDo: return "To do"
        case .inProgress: return "In progress"
        case .done: return "Completed"
        }
    }
}
