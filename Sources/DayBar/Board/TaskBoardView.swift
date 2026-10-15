import SwiftUI
import DayBarCore

/// A task scope rendered as a list or a 3-column kanban board (To Do / In Progress / Done).
/// Column membership is derived from `completedDate`/`status` — no extra state is stored.
/// All task data comes from one `BoardSnapshot` per render (no fetches in `body`).
///
/// Clicking a task selects it and shows it in the window's inspector. With the board
/// focused: ↑↓←→ move the selection, Space completes, Return opens the inspector, Delete
/// drops (undoable), 0–3 set priority, ⌘↑/⌘↓ reorder, ⌘←/⌘→ change column, Esc deselects.
struct TaskBoardView: View {
    let scope: TaskScope
    @Binding var selection: UUID?
    @Binding var inspectorPresented: Bool

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager
    @Environment(TaskDragCoordinator.self) private var dragCoordinator: TaskDragCoordinator?

    @State private var viewMode: TasksViewMode = .list
    @State private var todoPendingDelete: DailyTodo?
    @FocusState private var addFocused: Bool
    @FocusState private var boardFocused: Bool
    @State private var newTitle = ""
    @State private var composerDate: Date?
    @State private var showDatePopover = false

    private var scopeKey: String { appState.scopeKey(for: scope) }

    var body: some View {
        let snapshot = appState.boardSnapshot(for: scope)
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack(alignment: .bottom) {
                Group {
                    switch viewMode {
                    case .list: listView(snapshot)
                    case .kanban: kanbanView(snapshot)
                    }
                }
                .focusable()
                .focused($boardFocused)
                .focusEffectDisabled()
                .onKeyPress(phases: .down) { handleKey($0, snapshot: snapshot) }

                UndoToast(appState: appState, style: .floating)
                    .padding(.bottom, ThemeMetrics.spacingL)
            }
            Divider()
            addField
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
        .onChange(of: appState.windowCommand) { _, request in
            if let request { perform(request.command, snapshot: appState.boardSnapshot(for: scope)) }
        }
        .onChange(of: snapshot.orderedIDs) { _, ids in
            // A task that left this scope (dropped, moved, deleted) can't stay selected.
            if let selected = selection, !ids.contains(selected) { selection = nil }
        }
        .alert(
            "Delete task “\(todoPendingDelete?.title ?? "")” permanently?",
            isPresented: Binding(
                get: { todoPendingDelete != nil },
                set: { if !$0 { todoPendingDelete = nil } }
            )
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let todo = todoPendingDelete {
                    if selection == todo.id { selection = nil }
                    appState.deleteTodo(todo)
                }
                todoPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { todoPendingDelete = nil }
        } message: {
            Text("This removes the task and its checklist and can't be undone. Use Drop to keep the option.")
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
            Button {
                inspectorPresented.toggle()
            } label: {
                Label(inspectorPresented ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.right")
            }
            .labelStyle(.iconOnly)
            .help(inspectorPresented ? "Hide Inspector (⌥⌘I)" : "Show Inspector (⌥⌘I)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - List mode

    @ViewBuilder
    private func listView(_ snapshot: BoardSnapshot) -> some View {
        if snapshot.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !snapshot.done.isEmpty {
                            SectionHeader("Tasks").padding(.bottom, ThemeMetrics.spacingXS)
                        }
                        VStack(spacing: 0) {
                            ForEach(snapshot.open) { todo in
                                row(todo)
                                    .opacity(dragCoordinator?.draggingID == todo.id ? 0.35 : 1)
                                    .taskRowFrame(todo.id)
                                    .taskDraggable(todo.id, title: todo.title, coordinator: dragCoordinator)
                                    .id(todo.id)
                            }
                        }
                        .taskDropZone(
                            "board.list",
                            orderedIDs: snapshot.open.map(\.id),
                            reorderableCount: snapshot.open.count,
                            accepts: { snapshot.open.map(\.id).contains($0) },
                            onDrop: { id, index in
                                guard let todo = snapshot.byID[id] else { return false }
                                appState.moveTodo(todo, toIndex: index, in: snapshot.open)
                                return true
                            }
                        )
                        if !snapshot.done.isEmpty {
                            SectionHeader("Completed")
                                .padding(.top, ThemeMetrics.spacingL)
                                .padding(.bottom, ThemeMetrics.spacingXS)
                            ForEach(snapshot.done) { todo in
                                row(todo).id(todo.id)
                            }
                        }
                    }
                    .padding(.horizontal, ThemeMetrics.spacingXL - ThemeMetrics.rowHorizontalPadding)
                    .padding(.vertical, ThemeMetrics.spacingL)
                }
                .onChange(of: selection) { _, id in
                    guard let id else { return }
                    withThemeAnimation(.snap) { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func row(_ todo: DailyTodo) -> some View {
        BoardRowView(
            appState: appState,
            todo: todo,
            showProjectChip: showProjectChips,
            isSelected: selection == todo.id,
            onOpenDetails: { select(todo) },
            onDelete: { requestPermanentDelete(todo) },
            onDrop: { dropTask(todo, snapshot: appState.boardSnapshot(for: scope)) }
        )
    }

    // MARK: - Kanban mode

    @ViewBuilder
    private func kanbanView(_ snapshot: BoardSnapshot) -> some View {
        if snapshot.isEmpty {
            emptyState
        } else {
            KanbanBoardView(
                scope: scope,
                snapshot: snapshot,
                showProjectChip: showProjectChips,
                selection: selection,
                onSelect: { select($0) },
                onDelete: { requestPermanentDelete($0) },
                onDrop: { dropTask($0, snapshot: appState.boardSnapshot(for: scope)) }
            )
        }
    }

    // MARK: - Selection & actions

    private func select(_ todo: DailyTodo) {
        selection = todo.id
        inspectorPresented = true
        boardFocused = true
    }

    private func requestPermanentDelete(_ todo: DailyTodo) {
        todoPendingDelete = todo
    }

    /// Drop (the undoable "delete"): select the next task so keyboard flow continues, show
    /// the Undo toast, and register ⌘Z.
    private func dropTask(_ todo: DailyTodo, snapshot: BoardSnapshot) {
        let columns = navigationColumns(snapshot)
        let next = BoardNavigation.next(from: todo.id, in: columns, direction: .down)
        let fallback = BoardNavigation.next(from: todo.id, in: columns, direction: .up)
        let id = todo.id
        withThemeAnimation(.reorder) { appState.drop(todo) }
        if selection == id {
            selection = next != id ? next : (fallback != id ? fallback : nil)
        }
        undoManager?.registerUndo(withTarget: appState) { state in
            MainActor.assumeIsolated { state.restoreDropped(id) }
        }
        undoManager?.setActionName("Drop Task")
    }

    /// Columns for arrow navigation: one list in list mode, three in kanban.
    private func navigationColumns(_ snapshot: BoardSnapshot) -> [[UUID]] {
        switch viewMode {
        case .list: return [(snapshot.open + snapshot.done).map(\.id)]
        case .kanban: return BoardColumn.allCases.map { snapshot.todos(in: $0).map(\.id) }
        }
    }

    private func handleKey(_ press: KeyPress, snapshot: BoardSnapshot) -> KeyPress.Result {
        let command = press.modifiers.contains(.command)
        let selected = selection.flatMap { snapshot.byID[$0] }

        switch press.key {
        case .upArrow, .downArrow, .leftArrow, .rightArrow:
            if command, let todo = selected {
                return moveWithCommand(todo, key: press.key, snapshot: snapshot) ? .handled : .ignored
            }
            guard !press.modifiers.contains(.option), !press.modifiers.contains(.control) else { return .ignored }
            let direction: BoardNavigation.Direction
            switch press.key {
            case .upArrow: direction = .up
            case .downArrow: direction = .down
            case .leftArrow: direction = .left
            default: direction = .right
            }
            if viewMode == .list, direction == .left || direction == .right { return .ignored }
            selection = BoardNavigation.next(from: selection, in: navigationColumns(snapshot), direction: direction)
            return .handled
        case .escape:
            guard selection != nil else { return .ignored }
            selection = nil
            return .handled
        case .return:
            guard selected != nil else { return .ignored }
            inspectorPresented = true
            return .handled
        case .space:
            guard let todo = selected else { return .ignored }
            withThemeAnimation(.columnMove) { appState.toggleComplete(todo) }
            return .handled
        case .delete, .deleteForward:
            guard let todo = selected else { return .ignored }
            dropTask(todo, snapshot: snapshot)
            return .handled
        default:
            break
        }
        if press.modifiers.isEmpty, let todo = selected,
           let digit = Int(press.characters), let priority = Priority(level: digit) {
            appState.setPriority(todo, priority)
            return .handled
        }
        return .ignored
    }

    /// ⌘↑/⌘↓ reorder within the task's group; ⌘←/⌘→ change kanban column.
    private func moveWithCommand(_ todo: DailyTodo, key: KeyEquivalent, snapshot: BoardSnapshot) -> Bool {
        switch key {
        case .upArrow, .downArrow:
            guard !todo.isCompleted else { return false }
            let group = viewMode == .kanban ? snapshot.todos(in: todo.isInProgress ? .inProgress : .toDo) : snapshot.open
            withThemeAnimation(.reorder) {
                appState.moveTodo(todo, by: key == .upArrow ? -1 : 1, in: group)
            }
            return true
        case .leftArrow, .rightArrow:
            let columns = BoardColumn.allCases
            let current = todo.isCompleted ? BoardColumn.done : (todo.isInProgress ? .inProgress : .toDo)
            guard let index = columns.firstIndex(of: current) else { return false }
            let target = index + (key == .leftArrow ? -1 : 1)
            guard columns.indices.contains(target) else { return true }
            withThemeAnimation(.columnMove) { appState.setBoardStatus(columns[target], for: todo) }
            return true
        default:
            return false
        }
    }

    /// Task-menu commands from the main menu, applied to the selected task.
    private func perform(_ command: WindowCommand, snapshot: BoardSnapshot) {
        guard let todo = selection.flatMap({ snapshot.byID[$0] }) else { return }
        switch command {
        case .completeSelected:
            withThemeAnimation(.columnMove) { appState.toggleComplete(todo) }
        case .toggleStartSelected:
            withThemeAnimation(.columnMove) { appState.toggleInProgress(todo) }
        case .setPriority(let priority):
            appState.setPriority(todo, priority)
        case .moveSelectedToToday:
            appState.setPlannedDate(todo, to: .now)
        case .moveSelectedToTomorrow:
            appState.setPlannedDate(todo, to: DayMath.nextDay(.now, calendar: appState.calendar))
        case .dropSelected:
            dropTask(todo, snapshot: snapshot)
        case .toggleInspector:
            break // handled by the window
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
            .accessibilityLabel("Pick a date")
            .popover(isPresented: $showDatePopover, arrowEdge: .top) {
                ComposerDatePopover(scope: scope, calendar: appState.calendar, date: $composerDate)
            }
            if !newTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: addCurrent) {
                    Image(systemName: "return").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Add task")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: ThemeMetrics.fieldRadius, style: .continuous)
                .fill(addFocused ? ThemeColors.fieldFillFocused : ThemeColors.fieldFill)
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
        case .allTasks: return "All clear. Every task is done or dropped."
        case .project: return "No tasks in this project yet."
        }
    }
}
