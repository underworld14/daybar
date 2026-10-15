import SwiftUI
import DayBarCore

/// The main window's right-hand inspector: live details of the selected task.
struct TaskInspectorView: View {
    var appState: AppState
    let selectedID: UUID?

    var body: some View {
        // Read the revision so a task changed elsewhere (tray, Reminders) re-resolves here.
        let _ = appState.todosRevision
        if let todo = selectedTodo {
            TaskDetailForm(appState: appState, todo: todo)
                .id(todo.id)
        } else {
            ContentUnavailableView {
                Label("No Task Selected", systemImage: "sidebar.right")
            } description: {
                Text("Select a task to see and edit its details.")
            }
        }
    }

    private var selectedTodo: DailyTodo? {
        guard let selectedID, let todo = try? appState.store.todo(id: selectedID),
              todo.status != .dropped else { return nil }
        return todo
    }
}
