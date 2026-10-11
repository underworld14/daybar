import SwiftUI
import DayBarCore

/// A task scope rendered as a list or a 3-column kanban board (To Do / In Progress / Done).
/// Column membership is derived from `completedDate`/`status` — no extra state is stored.
struct TaskBoardView: View {
    let scope: TaskScope

    @Environment(AppState.self) private var appState

    @State private var viewMode: TasksViewMode = .list
    @State private var detailTodo: DailyTodo?
    @State private var todoPendingDelete: DailyTodo?
    @FocusState private var addFocused: Bool
    @State private var newTitle = ""

    private var scopeKey: String { appState.scopeKey(for: scope) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            switch viewMode {
            case .list:
                listView
            case .kanban:
                kanbanView
            }
        }
        .onAppear {
            viewMode = Preferences.tasksViewMode(for: scopeKey)
            appState.refresh()
        }
        .onChange(of: viewMode) { _, mode in
            Preferences.setTasksMode(mode, for: scopeKey)
        }
        .onChange(of: appState.windowAddTaskFocusSignal) { _, _ in
            addFocused = true
        }
        .sheet(item: $detailTodo) { todo in
            TodoDetailSheet(appState: appState, todo: todo)
        }
        .alert(
            "Delete task “\(todoPendingDelete?.title ?? "")”?",
            isPresented: Binding(
                get: { todoPendingDelete != nil },
                set: { if !$0 { todoPendingDelete = nil } }
            )
        ) {
            Button("Delete Task", role: .destructive) {
                if let todo = todoPendingDelete { appState.deleteTodo(todo) }
                todoPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { todoPendingDelete = nil }
        } message: {
            Text("This permanently removes the task, including its checklist.")
        }
        .animation(.snappy, value: columnIDs)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(scopeName)
                .font(.system(.title3, design: .rounded).weight(.semibold))
            Spacer()
            Picker("View", selection: $viewMode) {
                Label("List", systemImage: "list.bullet").tag(TasksViewMode.list)
                Label("Kanban", systemImage: "rectangle.split.3x1").tag(TasksViewMode.kanban)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - List mode

    private var listView: some View {
        VStack(spacing: 0) {
            if rows.isEmpty && doneRows.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(rows) { todo in
                            BoardRowView(
                                appState: appState,
                                todo: todo,
                                showProjectChip: showProjectChips,
                                onOpenDetails: { detailTodo = todo },
                                onDelete: { todoPendingDelete = todo }
                            )
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        if !doneRows.isEmpty {
                            Text("TASKS").font(.caption2.weight(.semibold)).tracking(0.5)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !doneRows.isEmpty {
                        Section {
                            ForEach(doneRows) { todo in
                                BoardRowView(
                                    appState: appState,
                                    todo: todo,
                                    showProjectChip: showProjectChips,
                                    onOpenDetails: { detailTodo = todo },
                                    onDelete: { todoPendingDelete = todo }
                                )
                                .listRowSeparator(.hidden)
                            }
                        } header: {
                            Text("COMPLETED").font(.caption2.weight(.semibold)).tracking(0.5)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
            Divider()
            addField
        }
    }

    // MARK: - Kanban mode

    private var kanbanView: some View {
        VStack(spacing: 0) {
            if rows.isEmpty && inProgressRows.isEmpty && doneRows.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        BoardColumnView(
                            appState: appState,
                            scope: scope,
                            column: .toDo,
                            todos: toDoTodos,
                            showProjectChip: showProjectChips,
                            findTodo: findTodo,
                            onOpenDetails: { detailTodo = $0 },
                            onDelete: { todoPendingDelete = $0 }
                        )
                        BoardColumnView(
                            appState: appState,
                            scope: scope,
                            column: .inProgress,
                            todos: inProgressRows,
                            showProjectChip: showProjectChips,
                            findTodo: findTodo,
                            onOpenDetails: { detailTodo = $0 },
                            onDelete: { todoPendingDelete = $0 }
                        )
                        BoardColumnView(
                            appState: appState,
                            scope: scope,
                            column: .done,
                            todos: doneRows,
                            showProjectChip: showProjectChips,
                            findTodo: findTodo,
                            onOpenDetails: { detailTodo = $0 },
                            onDelete: { todoPendingDelete = $0 }
                        )
                    }
                    .padding(12)
                }
            }
            Divider()
            addField
        }
    }

    // MARK: - Add field

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .foregroundStyle(addFocused ? Color.accentColor : .secondary)
            TextField("Add a task…", text: $newTitle)
                .textFieldStyle(.plain)
                .focused($addFocused)
                .onSubmit(addCurrent)
            if !newTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: addCurrent) {
                    Image(systemName: "return").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(addFocused ? 0.06 : 0.03))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func addCurrent() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let todo = scope == .tomorrow
            ? appState.addTodoForTomorrow(title: title)
            : appState.addTodo(title: title)
        if case .project(let id) = scope, let todo {
            appState.assign(todo: todo, to: appState.projects.first(where: { $0.id == id }))
        }
        newTitle = ""
        addFocused = true
    }

    // MARK: - Data

    private var scopeName: String {
        switch scope {
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .allTasks: return "All Tasks"
        case .project(let id): return appState.projects.first(where: { $0.id == id })?.name ?? "Project"
        }
    }

    /// Chips are noise inside a single-project board.
    private var showProjectChips: Bool {
        if case .project = scope { return false }
        return true
    }

    /// Incomplete (not started + in progress) todos for the scope.
    private var rows: [DailyTodo] {
        appState.windowTodos(for: scope).filter { $0.completedDate == nil }
    }

    private var toDoTodos: [DailyTodo] {
        rows.filter { !$0.isInProgress }
    }

    private var inProgressRows: [DailyTodo] {
        rows.filter { $0.isInProgress }
    }

    /// Done-column source per scope: today/tomorrow show the day's completed tasks,
    /// All Tasks the last 7 days, a project everything completed in it (all capped at 50).
    private var doneRows: [DailyTodo] {
        let cap = 50
        switch scope {
        case .today, .tomorrow:
            return Array(appState.windowTodos(for: scope).filter { $0.completedDate != nil }.prefix(cap))
        case .allTasks:
            let start = appState.calendar.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
            return Array(((try? appState.store.completedTodos(in: start..<Date.now)) ?? []).prefix(cap))
        case .project(let id):
            let completed = ((try? appState.store.todos(inProject: id)) ?? [])
                .filter { $0.completedDate != nil }
                .sorted { ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast) }
            return Array(completed.prefix(cap))
        }
    }

    private var columnIDs: [UUID] {
        toDoTodos.map(\.id) + inProgressRows.map(\.id) + doneRows.map(\.id)
    }

    private func findTodo(_ id: UUID) -> DailyTodo? {
        (toDoTodos + inProgressRows + doneRows).first(where: { $0.id == id })
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Text("No tasks here")
        } description: {
            Text(emptyMessage)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        switch scope {
        case .today: return "Nothing planned yet. Add a task below."
        case .tomorrow: return "Nothing planned for tomorrow yet."
        case .allTasks: return "All clear — every task is done or dropped."
        case .project: return "No tasks in this project yet."
        }
    }
}

// MARK: - List row

private struct BoardRowView: View {
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

            PriorityDot(priority: todo.priority)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpenDetails() }
        .contextMenu { contextMenu }
    }

    @ViewBuilder
    private var contextMenu: some View {
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

// MARK: - Kanban column

private struct BoardColumnView: View {
    var appState: AppState
    let scope: TaskScope
    let column: BoardColumn
    let todos: [DailyTodo]
    let showProjectChip: Bool
    let findTodo: (UUID) -> DailyTodo?
    let onOpenDetails: (DailyTodo) -> Void
    let onDelete: (DailyTodo) -> Void

    @State private var isTargeted = false
    @State private var addingTask = false
    @State private var newTitle = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Text(columnName).font(.subheadline.weight(.semibold))
                Text("\(todos.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
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
                        onOpenDetails: { onOpenDetails(todo) },
                        onDelete: { onDelete(todo) }
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(minWidth: 240, maxWidth: 320, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
            }
        }
        .dropDestination(for: String.self) { payload, _ in
            guard let idString = payload.first,
                  let id = UUID(uuidString: idString),
                  let todo = findTodo(id) else { return false }
            appState.setBoardStatus(column, for: todo)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
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
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            addingTask = false
            return
        }
        // Same add semantics as the scope's bottom field.
        let todo = scope == .tomorrow
            ? appState.addTodoForTomorrow(title: title)
            : appState.addTodo(title: title)
        if let todo {
            if case .project(let id) = scope {
                appState.assign(todo: todo, to: appState.projects.first(where: { $0.id == id }))
            }
            if column != .toDo {
                appState.setBoardStatus(column, for: todo)
            }
        }
        newTitle = ""
        addFocused = true
    }
}

// MARK: - Card

private struct BoardCardView: View {
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
        .contextMenu { contextMenu }
        .draggable(todo.id.uuidString)
    }

    @ViewBuilder
    private var contextMenu: some View {
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

// MARK: - Priority

/// Small colored dot mirroring the panel's priority ordering (high > medium > low > none).
struct PriorityDot: View {
    let priority: Priority

    var body: some View {
        Group {
            if priority != .none {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .help(helpText)
            }
        }
    }

    private var color: Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .secondary
        case .none: return .clear
        }
    }

    private var helpText: String {
        switch priority {
        case .high: return "High priority"
        case .medium: return "Medium priority"
        case .low: return "Low priority"
        case .none: return "No priority"
        }
    }
}
