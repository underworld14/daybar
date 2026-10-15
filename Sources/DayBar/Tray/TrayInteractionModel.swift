import Foundation
import Observation
import DayBarCore

/// Keyboard targeting for the tray: the hovered row, or a row picked with ↑/↓. Key events
/// arrive from `AppDelegate`'s local monitor (only when no text field is being edited).
@MainActor
@Observable
final class TrayInteractionModel {
    enum Key {
        case priority(Int)
        case up, down
        case moveUp, moveDown
        case complete
        case openDetails
        case escape
    }

    private(set) var hoveredTodoID: UUID?
    var selectedTodoID: UUID?

    @ObservationIgnored private let appState: AppState
    /// Set by the tray view: presents the details sheet for a task.
    @ObservationIgnored var openDetails: ((DailyTodo) -> Void)?

    init(appState: AppState) {
        self.appState = appState
    }

    var targetID: UUID? { selectedTodoID ?? hoveredTodoID }

    func hoverChanged(_ id: UUID, hovering: Bool) {
        if hovering {
            hoveredTodoID = id
            // The pointer takes over from a stale keyboard selection.
            if selectedTodoID != nil, selectedTodoID != id { selectedTodoID = nil }
        } else if hoveredTodoID == id {
            hoveredTodoID = nil
        }
    }

    /// Tasks in tray display order (Today, Tomorrow, Carried over).
    private var displayed: [DailyTodo] {
        appState.todayTodos + appState.tomorrowTodos + appState.carriedTodos
    }

    /// The incomplete tasks of the section containing `id` — the list a move happens in.
    private func movableSection(containing id: UUID) -> [DailyTodo]? {
        for section in [appState.todayTodos, appState.tomorrowTodos, appState.carriedTodos]
        where section.contains(where: { $0.id == id }) {
            return section.filter { $0.completedDate == nil }
        }
        return nil
    }

    /// Returns whether the key was consumed.
    func handle(_ key: Key) -> Bool {
        switch key {
        case .up, .down:
            let list = displayed
            guard !list.isEmpty else { return false }
            let current = targetID.flatMap { id in list.firstIndex(where: { $0.id == id }) }
            let next: Int
            switch (key, current) {
            case (.down, nil): next = 0
            case (.up, nil): next = list.count - 1
            case (.down, let index?): next = min(index + 1, list.count - 1)
            default: next = max((current ?? 0) - 1, 0)
            }
            selectedTodoID = list[next].id
            return true
        case .escape:
            guard selectedTodoID != nil else { return false }
            selectedTodoID = nil
            return true
        default:
            break
        }

        guard let id = targetID, let todo = displayed.first(where: { $0.id == id }) else { return false }
        switch key {
        case .priority(let level):
            guard let priority = Priority(level: level) else { return false }
            appState.setPriority(todo, priority)
        case .moveUp, .moveDown:
            guard !todo.isCompleted, let section = movableSection(containing: id) else { return false }
            withThemeAnimation(.reorder) {
                appState.moveTodo(todo, by: key == .moveUp ? -1 : 1, in: section)
            }
        case .complete:
            withThemeAnimation(.reorder) { appState.toggleComplete(todo) }
        case .openDetails:
            openDetails?(todo)
        default:
            return false
        }
        return true
    }
}

extension TrayInteractionModel.Key: Equatable {}
