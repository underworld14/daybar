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

    var body: some View {
        TaskCardView(
            configuration: .make(
                todo, appState: appState, showsProject: showProjectChip, showsDate: true, isSelected: isSelected
            ),
            actions: .make(todo, appState: appState, allowsRename: false, openDetails: onOpenDetails)
        ) {
            BoardTaskContextMenu(appState: appState, todo: todo, onOpenDetails: onOpenDetails, onDrop: onDrop, onDelete: onDelete)
        }
        .draggable(todo.id.uuidString)
    }
}
