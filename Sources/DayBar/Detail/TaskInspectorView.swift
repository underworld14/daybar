import SwiftUI
import DayBarCore

/// The main window's right-hand inspector: live details of the selected task.
struct TaskInspectorView: View {
    var appState: AppState
    /// The board's scope: its memoized snapshot resolves the selection without a fetch.
    let scope: TaskScope?
    let selectedID: UUID?

    var body: some View {
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
        guard let selectedID, let scope else { return nil }
        return appState.boardSnapshot(for: scope).byID[selectedID]
    }
}
