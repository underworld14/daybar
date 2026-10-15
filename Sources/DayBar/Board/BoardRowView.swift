import SwiftUI
import DayBarCore

/// A list-mode board row: the shared `TaskRowView` with project/date chips. Clicking the
/// row opens details.
struct BoardRowView: View {
    var appState: AppState
    let todo: DailyTodo
    let showProjectChip: Bool
    var onOpenDetails: () -> Void
    var onDelete: () -> Void = {}

    var body: some View {
        TaskRowView(
            configuration: .make(
                todo, appState: appState,
                showsProject: showProjectChip, showsDate: true,
                titleInteraction: .openDetailsOnClick
            ),
            actions: .make(todo, appState: appState, allowsRename: false, openDetails: onOpenDetails),
            showsMenuButton: false
        ) {
            BoardTaskContextMenu(appState: appState, todo: todo, onOpenDetails: onOpenDetails, onDelete: onDelete)
        }
        .onTapGesture(perform: onOpenDetails)
    }
}
