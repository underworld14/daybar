import SwiftUI
import DayBarCore

/// A list-mode board row: status button, title, chips, priority dot. Tap opens details.
struct BoardRowView: View {
    var appState: AppState
    let todo: DailyTodo
    let showProjectChip: Bool
    var onOpenDetails: () -> Void
    var onDelete: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Button {
                appState.advanceTodo(todo)
            } label: {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.isCompleted ? "Completed" : (todo.isInProgress ? "In progress" : "To do"))

            Text(todo.title)
                .strikethrough(todo.isCompleted)
                .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                .fontWeight(todo.isInProgress ? .medium : .regular)
                .lineLimit(2)

            if todo.hasNotes {
                Image(systemName: "note.text")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Has notes")
            }

            Spacer(minLength: 4)

            if showProjectChip, let project = appState.project(for: todo) {
                Label(project.name, systemImage: project.symbolName)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .foregroundStyle(.secondary)
            }

            if !todo.isCompleted,
               let label = DayLabel.relative(todo.plannedForDate, now: .now, calendar: appState.calendar) {
                Text(label)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .foregroundStyle(.secondary)
                    .help("Planned for \(label)")
            }

            PriorityDot(priority: todo.priority)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpenDetails() }
        .contextMenu {
            BoardTaskContextMenu(appState: appState, todo: todo, onOpenDetails: onOpenDetails, onDelete: onDelete)
        }
    }

    private var statusIcon: String {
        if todo.isCompleted { return "checkmark.circle.fill" }
        if todo.isInProgress { return "circle.inset.filled" }
        return "circle"
    }

    private var statusColor: Color {
        if todo.isCompleted { return .green }
        if todo.isInProgress { return .accentColor }
        return .secondary
    }
}
