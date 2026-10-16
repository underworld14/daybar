import SwiftUI
import DayBarCore

/// Details sheet for the tray and Task History: the shared `TaskDetailForm` with a header
/// and a Done button (⌘↩). Escape closes too; edits are saved either way.
struct TodoDetailSheet: View {
    var appState: AppState
    let todo: DailyTodo

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Task details")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Done (⌘↩)")
            }
            .padding()
            Divider()
            TaskDetailForm(appState: appState, todo: todo)
        }
        // The tray panel is 360pt wide; a wider sheet would be clipped by it.
        .frame(width: 360, height: 560)
    }
}
