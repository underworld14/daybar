import SwiftUI
import DayBarCore

/// A kanban card: the shared `TaskCardView`, draggable by task id.
struct BoardCardView: View {
    var appState: AppState
    let todo: DailyTodo
    let showProjectChip: Bool
    let onOpenDetails: () -> Void
    let onDelete: () -> Void

    var body: some View {
        TaskCardView(
            configuration: .make(todo, appState: appState, showsProject: showProjectChip, showsDate: true),
            actions: .make(todo, appState: appState, allowsRename: false, openDetails: onOpenDetails)
        ) {
            BoardTaskContextMenu(appState: appState, todo: todo, onOpenDetails: onOpenDetails, onDelete: onDelete)
        }
        .draggable(todo.id.uuidString)
    }
}
