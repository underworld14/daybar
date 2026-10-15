import SwiftUI
import DayBarCore

/// One kanban column: a fixed header (name, count, date + add buttons, inline composer)
/// above its own vertically scrolling card stack. Dropping a card here moves it to the column.
struct BoardColumnView: View {
    let scope: TaskScope
    let column: BoardColumn
    let todos: [DailyTodo]
    let showProjectChip: Bool
    let lookup: (UUID) -> DailyTodo?
    let selection: UUID?
    let onSelect: (DailyTodo) -> Void
    let onDelete: (DailyTodo) -> Void
    let onDrop: (DailyTodo) -> Void
    var namespace: Namespace.ID?

    @Environment(AppState.self) private var appState
    @Environment(TaskDragCoordinator.self) private var dragCoordinator: TaskDragCoordinator?

    @State private var addingTask = false
    @State private var newTitle = ""
    @State private var composerDate: Date?
    @State private var showDatePopover = false
    @FocusState private var addFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            header

            if addingTask {
                TextField("Add a task…", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .focused($addFocused)
                    .onSubmit(commitAdd)
                    .onExitCommand {
                        addingTask = false
                        newTitle = ""
                    }
            }

            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    if todos.isEmpty {
                        Text("Nothing here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(todos) { todo in
                            BoardCardView(
                                appState: appState,
                                todo: todo,
                                showProjectChip: showProjectChip,
                                isSelected: selection == todo.id,
                                onOpenDetails: { onSelect(todo) },
                                onDrop: { onDrop(todo) },
                                onDelete: { onDelete(todo) },
                                namespace: namespace
                            )
                            .id(todo.id)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.automatic)
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: ThemeMetrics.columnRadius, style: .continuous)
                .fill(isTargeted ? ThemeColors.dropTarget : ThemeColors.columnFill)
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: ThemeMetrics.columnRadius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
            }
        }
        .taskDropZone(
            zoneID,
            orderedIDs: todos.map(\.id),
            // Done is newest-first, not manually ordered: dropping there just completes.
            reorderableCount: column == .done ? 0 : todos.count,
            accepts: { lookup($0) != nil },
            onDrop: { id, index in
                guard let todo = lookup(id) else { return false }
                appState.moveTodo(todo, to: column, index: index, in: todos)
                return true
            }
        )
        .themeAnimation(.reveal, value: isTargeted)
    }

    private var zoneID: String { "board.\(column.rawValue)" }

    private var isTargeted: Bool { dragCoordinator?.activeZone == zoneID }

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(accent).frame(width: 7, height: 7)
            Text(columnName).font(.subheadline.weight(.semibold))
            Text("\(todos.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            if let planned = composerDate {
                Text(DayLabel.relative(planned, now: .now, calendar: appState.calendar) ?? "Today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button {
                showDatePopover.toggle()
            } label: {
                Image(systemName: "calendar.badge.plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(composerDate != nil ? Color.accentColor : .secondary)
            .help("Pick a date")
            .popover(isPresented: $showDatePopover, arrowEdge: .bottom) {
                ComposerDatePopover(scope: scope, calendar: appState.calendar, date: $composerDate)
            }
            Button {
                addingTask = true
                addFocused = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Add task to \(columnName)")
        }
    }

    private var columnName: String {
        switch column {
        case .toDo: return "To Do"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        }
    }

    private var accent: Color {
        switch column {
        case .toDo: return .gray
        case .inProgress: return .accentColor
        case .done: return .green
        }
    }

    private func commitAdd() {
        guard let draft = BoardComposer.draft(
            from: newTitle, scope: scope, column: column, pickedDate: composerDate, appState: appState
        ) else {
            addingTask = false
            return
        }
        withThemeAnimation(.reorder) { _ = appState.addTodo(draft) }
        newTitle = ""
        composerDate = nil
        addFocused = true
    }
}
