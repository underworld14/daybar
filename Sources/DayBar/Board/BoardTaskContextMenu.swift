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
        Divider()
        if todo.isCompleted {
            Button("Reset to To-Do") { withThemeAnimation(.columnMove) { appState.setBoardStatus(.toDo, for: todo) } }
        } else {
            Button("Complete") { withThemeAnimation(.columnMove) { appState.setBoardStatus(.done, for: todo) } }
            if todo.isInProgress {
                Button("Move Back to To-Do") { withThemeAnimation(.columnMove) { appState.setBoardStatus(.toDo, for: todo) } }
            } else {
                Button("Start") { withThemeAnimation(.columnMove) { appState.setBoardStatus(.inProgress, for: todo) } }
            }
        }
        Menu("Priority") {
            ForEach([Priority.high, .medium, .low, .none], id: \.self) { level in
                Button {
                    appState.setPriority(todo, level)
                } label: {
                    if level == todo.priority {
                        Label(level.displayName, systemImage: "checkmark")
                    } else {
                        Text(level.displayName)
                    }
                }
            }
        }
        if !todo.isCompleted {
            Menu("Move to Project") {
                Button("None") { appState.assign(todo: todo, to: nil) }
                ForEach(appState.projects) { project in
                    Button(project.name) { appState.assign(todo: todo, to: project) }
                }
            }
        }
        Divider()
        Button("Delete…", role: .destructive) { onDelete() }
    }
}
