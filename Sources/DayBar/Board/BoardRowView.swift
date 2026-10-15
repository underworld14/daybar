import SwiftUI
import DayBarCore

/// A list-mode board row: the shared `TaskRowView` with project/date chips. Clicking the
/// row selects it (and shows it in the inspector).
struct BoardRowView: View {
    var appState: AppState
    let todo: DailyTodo
    let showProjectChip: Bool
    var isSelected = false
    var onOpenDetails: () -> Void
    var onDelete: () -> Void = {}
    var onDrop: () -> Void = {}

    var body: some View {
        TaskRowView(
            configuration: .make(
                todo, appState: appState,
                showsProject: showProjectChip, showsDate: true,
                isSelected: isSelected,
                titleInteraction: .openDetailsOnClick
            ),
            actions: .make(todo, appState: appState, allowsRename: false, openDetails: onOpenDetails),
            showsMenuButton: false
        ) {
            BoardTaskContextMenu(appState: appState, todo: todo, onOpenDetails: onOpenDetails, onDrop: onDrop, onDelete: onDelete)
        }
        .onTapGesture(perform: onOpenDetails)
    }
}
