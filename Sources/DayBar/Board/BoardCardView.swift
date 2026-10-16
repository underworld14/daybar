import SwiftUI
import DayBarCore

/// A kanban card: the shared `TaskCardView`, draggable by task id.
struct BoardCardView: View {
    var appState: AppState
    let todo: DailyTodo
    let showProjectChip: Bool
    var isSelected = false
    let onOpenDetails: () -> Void
    let onDrop: () -> Void
    let onDelete: () -> Void
    /// Shared across columns so a card glides to its new column on a status change.
    var namespace: Namespace.ID?

    @Environment(TaskDragCoordinator.self) private var dragCoordinator: TaskDragCoordinator?

    var body: some View {
        TaskCardView(
            configuration: .make(
                todo, appState: appState, showsProject: showProjectChip, showsDate: true, isSelected: isSelected
            ),
            actions: .make(todo, appState: appState, allowsRename: false, openDetails: onOpenDetails)
        ) {
            BoardTaskContextMenu(appState: appState, todo: todo, onOpenDetails: onOpenDetails, onDrop: onDrop, onDelete: onDelete)
        }
        .modifier(MatchedCardGeometry(id: todo.id, namespace: namespace))
        .opacity(dragCoordinator?.draggingID == todo.id ? 0.35 : 1)
        .taskRowFrame(todo.id)
        .taskDraggable(todo.id, title: todo.title, coordinator: dragCoordinator)
    }
}

/// `matchedGeometryEffect` when a namespace is available.
private struct MatchedCardGeometry: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}
