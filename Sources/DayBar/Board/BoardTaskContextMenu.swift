import SwiftUI
import DayBarCore

/// Right-click menu shared by board rows and kanban cards.
struct BoardTaskContextMenu: View {
    var appState: AppState
    let todo: DailyTodo
    let onOpenDetails: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button("Open Details") { onOpenDetails() }
        if !todo.isCompleted {
            Menu("Move to Project") {
                Button("None") { appState.assign(todo: todo, to: nil) }
                ForEach(appState.projects) { project in
                    Button(project.name) { appState.assign(todo: todo, to: project) }
                }
            }
            Button("Move to In Progress") { appState.setBoardStatus(.inProgress, for: todo) }
            Button("Complete") { appState.setBoardStatus(.done, for: todo) }
        } else {
            Button("Reset to To Do") { appState.setBoardStatus(.toDo, for: todo) }
        }
        Divider()
        Button("Delete…", role: .destructive) { onDelete() }
    }
}
