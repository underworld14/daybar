import SwiftUI
import DayBarCore

/// A kanban card: title, project/date chips, notes glyph, priority dot. Draggable by id.
struct BoardCardView: View {
    var appState: AppState
    let todo: DailyTodo
    let showProjectChip: Bool
    let onOpenDetails: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(todo.title)
                .font(.subheadline)
                .fontWeight(todo.isInProgress ? .medium : .regular)
                .strikethrough(todo.isCompleted)
                .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if showProjectChip, let project = appState.project(for: todo) {
                    Label(project.name, systemImage: project.symbolName)
                        .font(.caption2)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
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
                if todo.hasNotes {
                    Image(systemName: "note.text")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                PriorityDot(priority: todo.priority)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { onOpenDetails() }
        .contextMenu {
            BoardTaskContextMenu(appState: appState, todo: todo, onOpenDetails: onOpenDetails, onDelete: onDelete)
        }
        .draggable(todo.id.uuidString)
    }
}
