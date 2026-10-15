import SwiftUI
import DayBarCore

/// A task scope rendered as a list or a 3-column kanban board (To Do / In Progress / Done).
/// Column membership is derived from `completedDate`/`status` — no extra state is stored.
/// All task data comes from one `BoardSnapshot` per render (no fetches in `body`).
struct TaskBoardView: View {
    let scope: TaskScope

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewMode: TasksViewMode = .list
    @State private var detailTodo: DailyTodo?
    @State private var todoPendingDelete: DailyTodo?
    @FocusState private var addFocused: Bool
    @State private var newTitle = ""
    @State private var composerDate: Date?
    @State private var showDatePopover = false

    private var scopeKey: String { appState.scopeKey(for: scope) }

    var body: some View {
        let snapshot = appState.boardSnapshot(for: scope)
        VStack(spacing: 0) {
            toolbar
            Divider()
            switch viewMode {
            case .list:
                listView(snapshot)
            case .kanban:
                kanbanView(snapshot)
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
        .animation(reduceMotion ? nil : .snappy, value: snapshot.orderedIDs)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(scopeName)
                .font(ThemeTypography.boardTitle)
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

    private func listView(_ snapshot: BoardSnapshot) -> some View {
        VStack(spacing: 0) {
            if snapshot.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(snapshot.open) { todo in
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
                        if !snapshot.done.isEmpty {
                            SectionHeader("Tasks")
                        }
                    }
                    if !snapshot.done.isEmpty {
                        Section {
                            ForEach(snapshot.done) { todo in
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
                            SectionHeader("Completed")
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

    private func kanbanView(_ snapshot: BoardSnapshot) -> some View {
        VStack(spacing: 0) {
            if snapshot.isEmpty {
                emptyState
            } else {
                KanbanBoardView(
                    scope: scope,
                    snapshot: snapshot,
                    showProjectChip: showProjectChips,
                    onOpenDetails: { detailTodo = $0 },
                    onDelete: { todoPendingDelete = $0 }
                )
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
            TextField("Add a task…  (!!! priority, besok, #project)", text: $newTitle)
                .textFieldStyle(.plain)
                .focused($addFocused)
                .onSubmit(addCurrent)
            if let planned = composerDate {
                Button {
                    composerDate = nil
                } label: {
                    Label(
                        DayLabel.relative(planned, now: .now, calendar: appState.calendar) ?? "Today",
                        systemImage: "xmark.circle.fill"
                    )
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear custom date")
            }
            Button {
                showDatePopover.toggle()
            } label: {
                Image(systemName: "calendar.badge.plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(composerDate != nil ? Color.accentColor : .secondary)
            .help("Pick a date")
            .popover(isPresented: $showDatePopover, arrowEdge: .top) {
                ComposerDatePopover(scope: scope, calendar: appState.calendar, date: $composerDate)
            }
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
        guard let draft = BoardComposer.draft(
            from: newTitle, scope: scope, column: .toDo, pickedDate: composerDate, appState: appState
        ) else { return }
        withThemeAnimation(.reorder) { _ = appState.addTodo(draft) }
        newTitle = ""
        composerDate = nil
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
