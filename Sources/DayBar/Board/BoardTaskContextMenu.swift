import SwiftUI
import DayBarCore

/// Right-click menu shared by board rows and kanban cards.
struct BoardTaskContextMenu: View {
    var appState: AppState
    let todo: DailyTodo
    let onOpenDetails: () -> Void
    let onDrop: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button("Show in Inspector") { onOpenDetails() }
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
            PriorityMenuItems(current: todo.priority) { appState.setPriority(todo, $0) }
        }
        if !todo.isCompleted {
            Menu("Move to Project") {
                Button("None") { appState.assign(todo: todo, to: nil) }
                ForEach(appState.projects) { project in
                    Button(project.name) { appState.assign(todo: todo, to: project) }
                }
            }
            Button("Move to Today") { withThemeAnimation(.reorder) { appState.plan(todo, for: .now) } }
            Button("Move to Tomorrow") {
                withThemeAnimation(.reorder) { appState.plan(todo, for: DayMath.nextDay(.now, calendar: appState.calendar)) }
            }
        }
        Divider()
        Button("Drop") { onDrop() }
        // Reminders mirrors would come back on the next pull; Drop syncs instead.
        if todo.source != .reminders {
            Button("Delete Permanently…", role: .destructive) { onDelete() }
        }
    }
}
